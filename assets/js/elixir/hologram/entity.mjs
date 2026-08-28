"use strict";

import Bitstring from "../../bitstring.mjs";
import Interpreter from "../../interpreter.mjs";
import Model from "../../model.mjs";
import Type from "../../type.mjs";
import Utils from "../../utils.mjs";

// Hologram.Entity's construction half, hand-written for the client for the reason the query
// stages are: the original asks the entity module for its declarations, and entity modules ship
// no reflection to the client - while the same declarations are baked into the bundle as the
// model, which this reads instead.
//
// What it answers is what the server answers, in the same words: every refusal below mirrors one
// in Hologram.Entity, and the tests are the Elixir ones case for case.
//
// One deliberate difference, in MISUSE rather than in behaviour: the original folds its values
// through Map.new/1, so handing it something that is neither a map nor a keyword list raises
// Protocol.UndefinedError. Rebuilding that exception here would say more about Enumerable than
// about entities, so the refusal below names what a caller may pass instead.

// The name every entity field carrying the framework's own state is spelled with. It is settable
// like any other field, which is what struct!/2 does with it, rather than being one of the
// declarations the model describes.
const METADATA_FIELD = "__meta__";

const ROLE_GRANT = "Hologram.Auth.RoleGrant";

const SERVER_ONLY_STRUCT = "Hologram.Entity.ServerOnly";

// The attributes every entity type carries without declaring them - Hologram.Entity's
// @system_attributes. Validation judges what a type DECLARES, so these are left out of it, which
// is what __attributes__/0 does on the server by simply not holding them. The model bakes them
// alongside the declared ones, because reading a row back needs their types.
const SYSTEM_ATTRIBUTES = ["created_at", "id", "updated_at"];

function attributeValue(entry, given, name) {
  if (given.has(name)) {
    return given.get(name);
  }

  if (name === "id") {
    return Elixir_Hologram_Entity["generate_id/0"]();
  }

  return entry.defaults[name] ?? Type.nil();
}

// The struct as Model.box builds one for a row, in the same field order, so a row constructed
// here and a row that arrived read alike: the type, the framework's own state, every declared
// and system attribute, and per relationship its reference field and the sentinel saying nobody
// asked for it.
function buildStruct(entityType, entry, pairs) {
  const given = new Map(pairs);

  const data = [
    [Type.atom("__struct__"), entityType],
    [
      Type.atom(METADATA_FIELD),
      given.get(METADATA_FIELD) ?? Model.emptyMetadata(),
    ],
  ];

  for (const name of Object.keys(entry.attributes)) {
    data.push([Type.atom(name), attributeValue(entry, given, name)]);
  }

  for (const [name, relationship] of Object.entries(entry.relationships)) {
    if (!relationship.toMany) {
      const referenceField = referenceFieldName(name);

      data.push([
        Type.atom(referenceField),
        given.get(referenceField) ?? Type.nil(),
      ]);
    }

    data.push([Type.atom(name), Model.notIncluded(name)]);
  }

  return Type.map(data);
}

// A map or a keyword list folded to [name, value] pairs the way Map.new/1 folds either - a name
// written twice keeps the value written last, which is what building the map from them does.
function fieldPairs(values) {
  if (Type.isMap(values)) {
    return Object.values(values.data).map(([key, value]) => [key.value, value]);
  }

  if (Type.isProperList(values)) {
    return values.data.map((pair) => [pair.data[0].value, pair.data[1]]);
  }

  Interpreter.raiseArgumentError(
    `${Interpreter.inspect(values)} is not a map or a keyword list of entity field values`,
  );
}

function newEntity(entityType, values) {
  const pairs = fieldPairs(values);
  const type = Interpreter.moduleExName(entityType);

  // Refused before the model is asked, as the server refuses it before reading any declaration:
  // a grant is written through grant_role/revoke_role and nowhere else.
  if (type === ROLE_GRANT) {
    Interpreter.raiseArgumentError(
      "role grants are written only through grant_role/revoke_role",
    );
  }

  const entry = Model.entry(type);

  refuseRelationshipAssignment(entry, type, pairs);
  refuseFrameworkAttribute(entry, type, pairs);
  refuseUnknownField(entry, pairs);

  return buildStruct(entityType, entry, pairs);
}

function referenceFieldName(relationshipName) {
  return `${relationshipName}_id`;
}

// A job is enqueued as queued, by whoever is acting, and what happens to it afterwards is the
// worker's to record - so the attributes carrying that are refused by name. The names are walked
// in the order the model lists them, which is the order the server's own search walks, so a
// construction naming two of them is refused for the same one on both tiers.
function refuseFrameworkAttribute(entry, type, pairs) {
  const given = new Map(pairs);
  const name = entry.frameworkAttributes.find((each) => given.has(each));

  if (name) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(Type.atom(name))} of ${type} is set by the framework - a job is enqueued as queued, and the worker records the rest`,
    );
  }
}

function refuseRelationshipAssignment(entry, type, pairs) {
  const given = new Map(pairs);
  const name = Object.keys(entry.relationships).find((each) => given.has(each));

  if (name) {
    Interpreter.raiseArgumentError(
      `relationship ${Interpreter.inspect(Type.atom(name))} of ${type} cannot be assigned at construction - set a to-one reference via the :${name}_id field, to-many edges via add_relationship`,
    );
  }
}

// What struct!/2 refuses on the server, in its words: a name that is no field of the struct.
// Relationship names are fields and are refused above instead, with the message that teaches the
// reference field to use.
function refuseUnknownField(entry, pairs) {
  const referenceFields = Object.entries(entry.relationships)
    .filter(([_name, relationship]) => !relationship.toMany)
    .map(([name]) => referenceFieldName(name));

  const settable = new Set([
    METADATA_FIELD,
    ...Object.keys(entry.attributes),
    ...referenceFields,
  ]);

  const unknown = pairs.find(([name]) => !settable.has(name));

  if (unknown) {
    Interpreter.raiseError(
      "KeyError",
      `key ${Interpreter.inspect(Type.atom(unknown[0]))} not found`,
    );
  }
}

function attributeDataErrors(entry, data, name, attributeType) {
  const optional = optionalAttribute(entry, name);

  if (!data.has(name)) {
    return optional ? [] : [errorTuple(name, Type.atom("required"))];
  }

  const value = data.get(name);

  if (Type.isNil(value)) {
    return optional ? [] : [errorTuple(name, Type.atom("required"))];
  }

  // A sentinel is not a value that failed a check, it is the absence of this client's permission
  // to see one - judging it would judge the reader rather than the data. What the client CAN
  // judge is a server-only attribute that is required and simply empty, which the clause above
  // reports the way the server does.
  if (Type.isStruct(value, SERVER_ONLY_STRUCT)) {
    return [];
  }

  return valueErrors(entry, name, value, attributeType);
}

function changeErrors(entry, name, value, attributeType) {
  if (Type.isNil(value)) {
    return optionalAttribute(entry, name)
      ? []
      : [errorTuple(name, Type.atom("required"))];
  }

  return valueErrors(entry, name, value, attributeType);
}

// The attributes a type DECLARES, which is what validation judges - the system ones the model
// bakes beside them are the framework's to fill.
function declaredAttributes(entry) {
  return Object.entries(entry.attributes).filter(
    ([name]) => !SYSTEM_ATTRIBUTES.includes(name),
  );
}

function errorTuple(name, reason) {
  return Type.tuple([Type.atom(name), reason]);
}

// The pairs a violation map is built from, sorted the way Elixir sorts the {name, reason} tuples
// they are - so an atom reason comes before a tuple one and names come in their own order,
// without this side spelling out a rule that already exists.
function groupErrors(errors) {
  if (errors.length === 0) {
    return Type.atom("ok");
  }

  const sorted = [...errors].sort(Interpreter.compareTerms);
  const grouped = new Map();

  for (const error of sorted) {
    const [name, reason] = error.data;
    const reasons = grouped.get(name.value) ?? [];

    grouped.set(name.value, [...reasons, reason]);
  }

  const violations = [...grouped].map(([name, reasons]) => [
    Type.atom(name),
    Type.list(reasons),
  ]);

  return Type.tuple([Type.atom("error"), Type.map(violations)]);
}

function optionalAttribute(entry, name) {
  return entry.constraints[name]?.optional === true;
}

// A to-one relationship is followed through a reference field holding an entity id, and that
// field is judged beside the attributes. A to-many has no field on the row to judge.
function referenceDefinitions(entry) {
  return Object.entries(entry.relationships)
    .filter(([_name, relationship]) => !relationship.toMany)
    .map(([name, relationship]) => [
      referenceFieldName(name),
      relationship.optional === true,
    ]);
}

function referenceErrors(data, field, optional) {
  if (!data.has(field) || Type.isNil(data.get(field))) {
    return optional ? [] : [errorTuple(field, Type.atom("required"))];
  }

  return referenceValueErrors(field, data.get(field));
}

function referenceValueErrors(field, value) {
  return uuidValue(value)
    ? []
    : [errorTuple(field, Type.tuple([Type.atom("type"), Type.atom("uuid")]))];
}

// Only the canonical lowercase 8-4-4-4-12 spelling, as on the server: the framework writes ids
// that way and both tiers compare them as strings, so any other spelling would match on one tier
// only.
function uuidValue(value) {
  if (!Type.isBinary(value)) {
    return false;
  }

  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
    Bitstring.toText(value),
  );
}

function validateChanges(entityType, changes) {
  const type = Interpreter.moduleExName(entityType);
  const entry = Model.entry(type);

  const attributeTypes = new Map(declaredAttributes(entry));
  const references = new Map(referenceDefinitions(entry));

  const errors = fieldPairs(changes).flatMap(([name, value]) => {
    if (attributeTypes.has(name)) {
      return changeErrors(entry, name, value, attributeTypes.get(name));
    }

    if (references.has(name)) {
      return Type.isNil(value)
        ? references.get(name)
          ? []
          : [errorTuple(name, Type.atom("required"))]
        : referenceValueErrors(name, value);
    }

    return [errorTuple(name, Type.atom("unknown"))];
  });

  return groupErrors(errors);
}

function validateEntity(entity) {
  if (
    !Type.isMap(entity) ||
    !(Type.encodeMapKey(Type.atom("__struct__")) in entity.data)
  ) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(entity)} is not an entity struct`,
    );
  }

  const entityType = entity.data[Type.encodeMapKey(Type.atom("__struct__"))][1];
  const entry = Model.entry(Interpreter.moduleExName(entityType));

  // What Map.take leaves on the server: the declared attributes and the to-one reference fields,
  // and nothing else - so a system attribute, a relationship and __meta__ are never judged, and
  // an undeclared name cannot be present to be reported.
  const data = new Map();

  for (const [name] of declaredAttributes(entry)) {
    data.set(name, entity.data[Type.encodeMapKey(Type.atom(name))][1]);
  }

  for (const [field] of referenceDefinitions(entry)) {
    data.set(field, entity.data[Type.encodeMapKey(Type.atom(field))][1]);
  }

  const attributeErrors = declaredAttributes(entry).flatMap(([name, type]) =>
    attributeDataErrors(entry, data, name, type),
  );

  const referenceDataErrors = referenceDefinitions(entry).flatMap(
    ([field, optional]) => referenceErrors(data, field, optional),
  );

  return groupErrors([...attributeErrors, ...referenceDataErrors]);
}

function valueErrors(entry, name, value, attributeType) {
  if (attributeType === "enum") {
    return enumErrors(entry, name, value);
  }

  if (!typeValid(value, attributeType)) {
    return [
      errorTuple(
        name,
        Type.tuple([Type.atom("type"), Type.atom(attributeType)]),
      ),
    ];
  }

  // TODO: the declared constraints are judged here, on a value that matched its type.
  return [];
}

function enumErrors(entry, name, value) {
  const declared = entry.enumValues[name];

  if (Type.isAtom(value) && declared.includes(Model.unbox(value, "enum"))) {
    return [];
  }

  return [
    errorTuple(
      name,
      Type.tuple([
        Type.atom("values"),
        Type.list(declared.map((label) => Model.boxEnumValue(label))),
      ]),
    ),
  ];
}

// Postgres int8 bounds, which is what an integer attribute is stored in.
function typeValid(value, attributeType) {
  switch (attributeType) {
    case "boolean":
      return Type.isBoolean(value);

    case "date":
      return Type.isStruct(value, "Date");

    case "datetime":
      return Type.isStruct(value, "DateTime");

    case "float":
      return Type.isFloat(value);

    case "integer":
      return (
        Type.isInteger(value) &&
        value.value >= -9223372036854775808n &&
        value.value <= 9223372036854775807n
      );

    case "string":
      return Type.isBinary(value) && Bitstring.isText(value);

    default:
      return uuidValue(value);
  }
}

const Elixir_Hologram_Entity = {
  "generate_id/0": () => Type.bitstring(Utils.uuidv7()),

  "new/1": (entityType) => newEntity(entityType, Type.map([])),

  "new/2": (entityType, values) => newEntity(entityType, values),

  "validate/1": (entity) => validateEntity(entity),

  "validate/2": (entityType, changes) => validateChanges(entityType, changes),
};

export default Elixir_Hologram_Entity;
