"use strict";

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

const Elixir_Hologram_Entity = {
  "generate_id/0": () => Type.bitstring(Utils.uuidv7()),

  "new/1": (entityType) => newEntity(entityType, Type.map([])),

  "new/2": (entityType, values) => newEntity(entityType, values),
};

export default Elixir_Hologram_Entity;
