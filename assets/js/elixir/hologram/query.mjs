"use strict";

import Interpreter from "../../interpreter.mjs";
import Model from "../../model.mjs";
import Type from "../../type.mjs";

// The query stages, hand-written for the client the way the low-level Erlang functions are.
//
// What they build is a PLAIN term - the shape the kernel evaluates and the database is read by -
// rather than the boxed map the transpiled stages would build. A builder is ordinary app code
// piping these together, so nothing between the stages reads the term: it is constructed here,
// handed to the kernel, and never pattern-matched on the way.
//
// Validation is the reason these are ports rather than the transpiled originals. The originals
// ask the entity module for its attributes, and entity modules ship no reflection to the client -
// but the same declarations are baked into the bundle as the model, which these read instead.
// What is checked is what the server checks, in the same words: the ArgumentError messages are
// mirrored, and the consistency suite pins them.

const EQUALITY_OPERATORS = ["!=", "=="];
const MEMBERSHIP_OPERATORS = ["in", "not_in"];
const ORDERABLE_TYPES = [
  "date",
  "datetime",
  "enum",
  "float",
  "integer",
  "string",
  "time",
];
const ORDERING_OPERATORS = ["<", "<=", ">", ">="];

// The names an attribute may be ordered or read by - declared and system alike, sorted, the way
// the model bakes them. Reference fields are deliberately absent, as they are on the server: a
// relationship is followed, not ordered by.
function attributeNames(entityType) {
  return Object.keys(Model.entry(entityType).attributes);
}

// A name matching no attribute definition is a to-one reference field, and every one of those
// carries an entity id - the fallback both tiers make.
function attributeType(entityType, name) {
  return Model.entry(entityType).attributes[name] ?? "uuid";
}

// A counter is an integer attribute that always holds a number: an optional one can be nil, and
// there is nothing to add to nil.
function counterAttributeNames(entityType) {
  const constraints = Model.entry(entityType).constraints;

  return integerNames(entityType).filter(
    (name) => constraints[name]?.optional !== true,
  );
}

// The entity type of a struct a stage was handed, or a raise in the server's words. What the
// client can check is that the build carries the type, which is its whole notion of "is an entity".
function entityTypeOf(entity, stage) {
  const type = Model.structTypeName(entity);

  if (type !== null && Model.isEntityType(type)) {
    return type;
  }

  Interpreter.raiseArgumentError(
    `${stage} takes an entity struct, got: ${Interpreter.inspect(entity)}`,
  );
}

function integerNames(entityType) {
  return attributeNames(entityType).filter(
    (name) => attributeType(entityType, name) === "integer",
  );
}

// The field previews the result the way a put value does - only the recorded amount is written, so
// the row still computes its value from whatever it holds at the write.
//
// A declared integer attribute holds an integer, the server-only sentinel, or nil, and each is a
// different answer: the sentinel is not a number this client is missing but one it is not for, so
// no read produces it and the refusal must not send anyone looking.
function movedValue(entity, name, entityType, delta, stage) {
  const value = field(entity, name.value);

  if (Type.isInteger(value)) {
    return Type.integer(value.value + delta);
  }

  if (Model.structTypeName(value) === "Hologram.Entity.ServerOnly") {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(name)} of ${entityType} is server-only - a browser cannot write it, set it in a command or a job`,
    );
  }

  Interpreter.raiseArgumentError(
    `${Interpreter.inspect(name)} in ${entityType} holds nil - a counter always holds a number, so there is nothing for ${stage} to move - read the row first, or give the attribute a default`,
  );
}

function orderEntries(spec, entityType) {
  if (Type.isAtom(spec)) {
    return [orderEntry(spec, entityType)];
  }

  if (Type.isList(spec)) {
    return spec.data.map((entry) => orderEntry(entry, entityType));
  }

  Interpreter.raiseArgumentError(
    `order_by spec must be an attribute name or a list, got: ${Interpreter.inspect(spec)}`,
  );
}

// Every attribute type is an ordering key, enums included: an enum orders by the position of its
// value in the declared list, which the kernel reads from the model.
function orderEntry(entry, entityType) {
  if (Type.isAtom(entry)) {
    validateAttributeName(entry, entityType, "ordered");

    return [entry.value, "asc"];
  }

  if (
    Type.isTuple(entry) &&
    entry.data.length === 2 &&
    Type.isAtom(entry.data[0])
  ) {
    const [name, direction] = entry.data;

    validateAttributeName(name, entityType, "ordered");

    if (!Type.isAtom(direction) || !["asc", "desc"].includes(direction.value)) {
      Interpreter.raiseArgumentError(
        `invalid direction ${Interpreter.inspect(direction)} for attribute ${Interpreter.inspect(name)} - use :asc or :desc`,
      );
    }

    return [name.value, direction.value];
  }

  Interpreter.raiseArgumentError(
    `invalid order_by entry ${Interpreter.inspect(entry)} - use an attribute name or an {attribute, :asc | :desc} tuple`,
  );
}

function field(struct, name) {
  return struct.data[Type.encodeMapKey(Type.atom(name))][1];
}

// The names a predicate may read: the attributes plus the reference field of every to-one
// relationship, which carries an entity id and so filters like any uuid attribute.
function filterableNames(entityType) {
  return [
    ...attributeNames(entityType),
    ...referenceFieldNames(entityType),
  ].sort();
}

function includeDepth(term) {
  const subTerms = Object.values(term.include);

  return subTerms.length === 0
    ? 0
    : 1 + Math.max(...subTerms.map(includeDepth));
}

// The sub-builder is handed a fresh term for the related type, so what it returns is a query in
// its own right - filtered, ordered and bounded like any other - which is then embedded under the
// relationship's name.
function includeOne(query, name, subBuilder) {
  const term = toTerm(query);
  const {kind, target} = validateRelationshipName(name, term.entity);

  if (name.value in term.include) {
    Interpreter.raiseArgumentError(
      `relationship ${Interpreter.inspect(name)} is already included`,
    );
  }

  const relatedBaseTerm = toTerm(Type.alias(target));

  const subTerm = subBuilder
    ? Interpreter.callAnonymousFunction(subBuilder, [relatedBaseTerm])
    : relatedBaseTerm;

  validateSubTerm(subTerm, name, target, kind);

  return {...term, include: {...term.include, [name.value]: subTerm}};
}

// A spec entry is a relationship name, a {name, sub-builder} pair, or a {name, nested spec} pair -
// the last traversing deeper without writing a function for it.
function includeSpecEntry(term, entry) {
  const include = Elixir_Hologram_Query["include/3"];

  if (Type.isAtom(entry)) {
    return include(term, entry, Type.nil());
  }

  if (isConstraintTuple(entry)) {
    const [name, spec] = entry.data;

    return Type.isAnonymousFunction(spec)
      ? include(term, name, spec)
      : includeOne(term, name, nestedSubBuilder(spec));
  }

  Interpreter.raiseArgumentError(
    `invalid include spec entry ${Interpreter.inspect(entry)} - use a relationship name, a {name, spec} pair, or a {name, sub_builder} pair`,
  );
}

// A label beginning with an uppercase letter names a module, which is the rule the model reads
// row values by - boxed back that way, the interpreter spells the list exactly as Elixir's own
// inspect spells the declared one.
function inspectEnumValues(values) {
  const atoms = values.map((label) =>
    label[0] >= "A" && label[0] <= "Z" ? Type.alias(label) : Type.atom(label),
  );

  return Interpreter.inspect(Type.list(atoms));
}

function isActor(value) {
  return Type.isAtom(value) && value.value === "actor";
}

// A two-element tuple led by an atom - what an operator predicate looks like, and what tells a
// list of them from a list of plain values.
function isConstraintTuple(value) {
  return (
    Type.isTuple(value) && value.data.length === 2 && Type.isAtom(value.data[0])
  );
}

function isPlainValue(value) {
  return (
    !Type.isTuple(value) && !Type.isList(value) && !isStruct(value, "Range")
  );
}

// A stage returns the plain term this file builds, so what a sub-builder gives back is told from
// anything else by being one - a boxed value never carries an entity.
function isQueryTerm(value) {
  return value !== null && typeof value === "object" && "entity" in value;
}

function isStruct(value, name) {
  if (!Type.isMap(value)) {
    return false;
  }

  const entry = value.data[Type.encodeMapKey(Type.atom("__struct__"))];

  return !!entry && Type.isAlias(entry[1]) && structName(value) === name;
}

// A list is either a membership shorthand or a conjunction of operator tuples - never a mix,
// since the two read the same at a glance and mean opposite things.
function listTriples(name, list, entityType) {
  const values = list.data;

  if (values.length === 0) {
    Interpreter.raiseArgumentError(
      `filter list for attribute ${Interpreter.inspect(name)} must not be empty`,
    );
  }

  if (values.every(isConstraintTuple)) {
    return values.flatMap((value) => predicateTriples(name, value, entityType));
  }

  if (values.every(isPlainValue)) {
    validateMembershipList(list, name, "in");

    return [
      [name.value, "in", membershipValues(values, name.value, entityType)],
    ];
  }

  Interpreter.raiseArgumentError(
    `invalid filter list ${Interpreter.inspect(list)} for attribute ${Interpreter.inspect(name)} - use either a membership list of plain values or a list of operator tuples`,
  );
}

function membershipValues(values, name, entityType) {
  return values.map((value) =>
    isStruct(value, "Hologram.Query.Placeholder")
      ? placeholderLeaf(value)
      : Model.unbox(value, attributeType(entityType, name)),
  );
}

// The nested-spec shorthand is the sub-builder that includes through the nested spec, boxed the
// way a builder's own function arrives - so one code path calls both.
function nestedSubBuilder(spec) {
  const clause = {
    params: (_context) => [Type.variablePattern("related_term")],
    guards: [],
    body: (context) =>
      Elixir_Hologram_Query["include/2"](context.vars.related_term, spec),
  };

  return Type.anonymousFunction(1, [clause], Interpreter.buildContext());
}

function normalizedIncludes(term) {
  return Object.fromEntries(
    Object.entries(term.include).map(([name, subTerm]) => {
      const {kind} = validateRelationshipName(Type.atom(name), term.entity);

      return [
        name,
        kind === "to_many"
          ? normalizedTerm(subTerm)
          : {...subTerm, include: normalizedIncludes(subTerm)},
      ];
    }),
  );
}

// Every set-returning shape gets a total order, since two rows the ordering does not tell apart
// would otherwise come back in whatever order the rows happen to sit in. A count is order-blind,
// and a to-one embeds a single entity, so neither takes one.
function normalizedOrder(term) {
  if (term.cardinality === "count") {
    return [];
  }

  return term.orderBy.some(([name]) => name === "id")
    ? term.orderBy
    : [...term.orderBy, ["id", "asc"]];
}

function normalizedTerm(term) {
  return {
    ...term,
    filter: sortedFilter(term.filter),
    include: normalizedIncludes(term),
    orderBy: normalizedOrder(term),
  };
}

function operatorTriples(name, tuple, entityType) {
  const [operatorAtom, operand] = tuple.data;
  const operator = operatorAtom.value;

  if (isStruct(operand, "Range") && operator === "in") {
    return rangeTriples(name, operand, entityType);
  }

  if (isStruct(operand, "Hologram.Query.Placeholder")) {
    if (ORDERING_OPERATORS.includes(operator)) {
      validateOrderableAttribute(name, entityType, operator);
    } else if (
      !EQUALITY_OPERATORS.includes(operator) &&
      !MEMBERSHIP_OPERATORS.includes(operator)
    ) {
      raiseUnknownOperator(operator, name);
    }

    return [[name.value, operator, placeholderLeaf(operand)]];
  }

  if (EQUALITY_OPERATORS.includes(operator) && isActor(operand)) {
    validateActorAttribute(name, entityType);

    return [[name.value, operator, {actor: true}]];
  }

  if (EQUALITY_OPERATORS.includes(operator)) {
    validateScalarOperand(name, operator, operand);

    return [
      [
        name.value,
        operator,
        Model.unbox(operand, attributeType(entityType, name.value)),
      ],
    ];
  }

  if (MEMBERSHIP_OPERATORS.includes(operator)) {
    validateMembershipList(operand, name, operator);

    return [
      [
        name.value,
        operator,
        membershipValues(operand.data, name.value, entityType),
      ],
    ];
  }

  if (ORDERING_OPERATORS.includes(operator)) {
    validateOrderableAttribute(name, entityType, operator);
    validateScalarOperand(name, operator, operand, true);
    validateEnumOperand(name, operand, entityType);

    return [
      [
        name.value,
        operator,
        Model.unbox(operand, attributeType(entityType, name.value)),
      ],
    ];
  }

  raiseUnknownOperator(operator, name);
}

function placeholderLeaf(placeholder) {
  return {placeholder: field(placeholder, "name").value};
}

// Every shape a predicate value can take, dispatched in the order the Elixir clauses are written
// in - the shapes that are structures (a range, a placeholder, the actor) before the general tuple, and
// the general tuple before the plain value a bare term falls through to.
function predicateTriples(name, value, entityType) {
  if (isStruct(value, "Range")) {
    return rangeTriples(name, value, entityType);
  }

  if (isStruct(value, "Hologram.Query.Placeholder")) {
    return [[name.value, "==", placeholderLeaf(value)]];
  }

  if (
    Type.isTuple(value) &&
    value.data.length === 1 &&
    isActor(value.data[0])
  ) {
    validateActorAttribute(name, entityType);

    return [[name.value, "==", {actor: true}]];
  }

  if (isConstraintTuple(value)) {
    return operatorTriples(name, value, entityType);
  }

  if (Type.isTuple(value)) {
    Interpreter.raiseArgumentError(
      `invalid filter value ${Interpreter.inspect(value)} for attribute ${Interpreter.inspect(name)}`,
    );
  }

  if (Type.isList(value)) {
    return listTriples(name, value, entityType);
  }

  return [
    [
      name.value,
      "==",
      Model.unbox(value, attributeType(entityType, name.value)),
    ],
  ];
}

function raiseUnknownOperator(operator, name) {
  Interpreter.raiseArgumentError(
    `unknown operator :${operator} in the filter predicate for attribute ${Interpreter.inspect(name)} - supported operators: :!=, :<, :<=, :==, :>, :>=, :in, :not_in`,
  );
}

// A range is two bounds rather than a membership set - it says the same thing about an integer
// attribute in the words the two comparisons already have.
function rangeTriples(name, range, entityType) {
  validateMembershipRange(range, name, entityType);

  return [
    [name.value, ">=", Number(field(range, "first").value)],
    [name.value, "<=", Number(field(range, "last").value)],
  ];
}

// The names a put may set: the DECLARED attributes and every to-one relationship's reference
// field, sorted - the server's settable_names/1. A server-only attribute IS in this list, because
// server code may put one: it is the WRITE that refuses a client's, by name, rather than the stage
// pretending the attribute is not there.
function settableNames(entityType) {
  const declared = attributeNames(entityType).filter(
    (name) => !Model.systemAttributes.includes(name),
  );

  return [...declared, ...referenceFieldNames(entityType)].sort();
}

function structName(value) {
  return field(value, "__struct__").value.replace(/^Elixir\./, "");
}

function subTermHasClauses(subTerm) {
  return (
    subTerm.filter.length > 0 ||
    subTerm.orderBy.length > 0 ||
    subTerm.limit !== null ||
    subTerm.offset !== null
  );
}

function referenceFieldNames(entityType) {
  return toOneRelationshipNames(entityType).map((name) => `${name}_id`);
}

function relationshipNames(entityType) {
  return Object.keys(Model.entry(entityType).relationships);
}

// A cardinality marker is a terminal: a query cannot be two kinds of answer at once.
function setCardinality(query, cardinality) {
  const term = toTerm(query);

  if (term.cardinality !== "set") {
    Interpreter.raiseArgumentError(
      `cardinality is already set to :${term.cardinality}`,
    );
  }

  return {...term, cardinality: cardinality};
}

function setViewBound(query, field, value) {
  const term = toTerm(query);

  if (!Type.isInteger(value) || value.value < 0n) {
    Interpreter.raiseArgumentError(
      `${field} must be a non-negative integer, got: ${Interpreter.inspect(value)}`,
    );
  }

  return {...term, [field]: Number(value.value)};
}

// Conjunction is commutative, so the order predicates were written in carries nothing - one
// canonical order is what makes two spellings of the same query the same term. What that is FOR
// is the server's: it hashes the normalized term into the query's content id, and two spellings
// hashing apart would register, cache and scope one query twice. The kernel here evaluates the
// filter as a conjunction, so this side is indifferent to the order - it is sorted because
// normalize is one function, mirrored.
//
// The order itself is this tier's own, and cannot be the server's: the operands are already the
// wire spellings here ("2026-08-18") where the server holds Elixir values (~D[2026-08-18]), so
// ordering them by anything orders them differently. Nothing compares the two, and nothing may:
// a hash taken of a term on this side is NOT the server's content id for that query. If one is
// ever needed here, it comes from the server.
function sortedFilter(filter) {
  return [...filter].sort((left, right) => {
    const [leftKey, rightKey] = [left, right].map(([name, operator, operand]) =>
      [name, operator, JSON.stringify(operand ?? null)].join("\u0000"),
    );

    return leftKey < rightKey ? -1 : leftKey > rightKey ? 1 : 0;
  });
}

// A stage takes either the module a query starts from or the term a previous stage returned. A
// term is a plain object here, so it is told from a boxed module by being one.
//
// Membership in the model is what stands for the entity check: the model carries every type
// this client can hold, so a name missing from it is either not an entity type or one whose
// rows never reach a client - neither is a query this side can answer.
function systemAttributeNames(entityType) {
  return attributeNames(entityType).filter((name) =>
    Model.systemAttributes.includes(name),
  );
}

function toManyRelationshipNames(entityType) {
  return Object.entries(Model.entry(entityType).relationships)
    .filter(([_name, relationship]) => relationship.toMany)
    .map(([name]) => name);
}

function toOneRelationshipNames(entityType) {
  return Object.entries(Model.entry(entityType).relationships)
    .filter(([_name, relationship]) => !relationship.toMany)
    .map(([name]) => name);
}

function toTerm(query) {
  if (isQueryTerm(query)) {
    return query;
  }

  const name = Type.isAlias(query) ? Interpreter.moduleExName(query) : null;

  if (name === null || !(name in (globalThis.Hologram.sync?.model ?? {}))) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(query)} is not an entity type module or a query term - a query starts from a module with the "use Hologram.Entity" directive`,
    );
  }

  return {
    cardinality: "set",
    entity: name,
    filter: [],
    include: {},
    limit: null,
    offset: null,
    orderBy: [],
  };
}

// The actor leaf carries the acting user's entity id, so it compares only against names holding
// one - any other type would build a comparison that never matches.
// A second claim is refused where it is written: a struct carrying two authorities would have to
// pick one at the write, silently.
function putClaim(entity, claim, stage) {
  const entityType = entityTypeOf(entity, stage);
  const metadata = field(entity, "__meta__");
  const recorded = field(metadata, "claim");

  if (!Type.isNil(recorded)) {
    Interpreter.raiseArgumentError(
      `${entityType} already carries a claim (${Interpreter.inspect(recorded)}) - a write claims exactly one authority`,
    );
  }

  return putField(
    entity,
    Type.atom("__meta__"),
    putField(metadata, Type.atom("claim"), claim),
  );
}

// The two counter stages share everything but the sign they record. A sum that reaches zero is
// dropped rather than recorded: a delta of nothing is not a change, and the wire refuses one.
function putDelta(entity, name, amount, sign, stage) {
  const entityType = entityTypeOf(entity, stage);

  validateDeltaName(name, entityType, stage);
  validateAmount(amount, stage);

  const metadata = field(entity, "__meta__");
  const ops = field(metadata, "attribute_ops");
  const recorded = ops.data[Type.encodeMapKey(name)]?.[1] ?? null;
  const moved = BigInt(sign) * amount.value;

  // Stages apply in order: a move after a put folds into the value, so the attribute keeps one op.
  if (recorded !== null && recorded.data[0].value === "put") {
    const value = recorded.data[1];

    if (!Type.isInteger(value)) {
      Interpreter.raiseArgumentError(
        `${Interpreter.inspect(name)} in ${entityType} carries a put value that is not an integer (${Interpreter.inspect(value)}) - ${stage} cannot move it`,
      );
    }

    return Elixir_Hologram_Query["put_attribute/3"](
      entity,
      name,
      Type.integer(value.value + moved),
    );
  }

  const delta = (recorded === null ? 0n : recorded.data[1].value) + moved;
  const updatedOps = Type.cloneMap(ops);
  const key = Type.encodeMapKey(name);

  if (delta === 0n) {
    delete updatedOps.data[key];
  } else {
    updatedOps.data[key] = [
      name,
      Type.tuple([Type.atom("increment"), Type.integer(delta)]),
    ];
  }

  const moved_entity = putField(
    entity,
    name,
    movedValue(entity, name, entityType, moved, stage),
  );

  return putField(
    moved_entity,
    Type.atom("__meta__"),
    putField(metadata, Type.atom("attribute_ops"), updatedOps),
  );
}

// The two edge stages share everything but the operation they record. The relationship's own
// field is left alone: an edge is recorded, not applied, and what the field holds is whatever the
// read put there.
function putRelationshipOp(entity, relationshipName, targetId, op, stage) {
  const entityType = entityTypeOf(entity, stage);

  validateEdgeRelationshipName(relationshipName, entityType);

  if (!Type.isBitstring(targetId)) {
    Interpreter.raiseArgumentError(
      `${stage} takes a target id string, got: ${Interpreter.inspect(targetId)}`,
    );
  }

  const metadata = field(entity, "__meta__");
  const ops = Type.cloneMap(field(metadata, "relationship_ops"));
  const key = Type.tuple([relationshipName, targetId]);

  ops.data[Type.encodeMapKey(key)] = [key, Type.atom(op)];

  return putField(
    entity,
    Type.atom("__meta__"),
    putField(metadata, Type.atom("relationship_ops"), ops),
  );
}

// Records one op per attribute, the later put replacing whatever the attribute carried - an
// earlier put or an increment alike, since stages apply in order.
function putAttributes(entity, pairs) {
  const metadata = field(entity, "__meta__");
  const ops = Type.cloneMap(field(metadata, "attribute_ops"));
  let updated = entity;

  for (const [name, value] of pairs) {
    ops.data[Type.encodeMapKey(name)] = [
      name,
      Type.tuple([Type.atom("put"), value]),
    ];

    updated = putField(updated, name, value);
  }

  return putField(
    updated,
    Type.atom("__meta__"),
    putField(metadata, Type.atom("attribute_ops"), ops),
  );
}

function putField(struct, key, value) {
  const updated = Type.cloneMap(struct);

  updated.data[Type.encodeMapKey(key)] = [key, value];

  return updated;
}

// The pairs a put was given, a keyword list and a map alike. A name repeated in one list is left
// as the two pairs it arrived as rather than folded: applying them in order sets the later value
// and records the later op, which is exactly what Map.new/1 leaves the server with.
function putPairs(values, stage) {
  const entries = Type.isList(values)
    ? Type.isKeywordList(values) && values.data.map((pair) => pair.data)
    : Type.isMap(values) && Object.values(values.data);

  if (!entries) {
    Interpreter.raiseArgumentError(
      `${stage} takes a keyword list or a map of attribute values, got: ${Interpreter.inspect(values)}`,
    );
  }

  return entries;
}

function validateActorAttribute(name, entityType) {
  const type = attributeType(entityType, name.value);

  if (type !== "uuid") {
    Interpreter.raiseArgumentError(
      `user_id() requires a uuid attribute - attribute ${Interpreter.inspect(name)} in ${entityType} has type :${type}`,
    );
  }
}

function validateAttributeName(name, entityType, usage) {
  const names = attributeNames(entityType);

  if (names.includes(name.value)) {
    return;
  }

  if (relationshipNames(entityType).includes(name.value)) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(name)} is a relationship in ${entityType} - only attributes can be ${usage}`,
    );
  }

  const known = names.map((known) => `:${known}`).join(", ");

  Interpreter.raiseArgumentError(
    `unknown attribute ${Interpreter.inspect(name)} in ${entityType} - known attributes: ${known}`,
  );
}

function validateFilteredName(name, entityType) {
  const names = filterableNames(entityType);

  if (names.includes(name.value)) {
    return;
  }

  const relationship = Model.entry(entityType).relationships[name.value];

  if (relationship && !relationship.toMany) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(name)} is a relationship in ${entityType} - only attributes can be filtered - filter its reference via :${name.value}_id`,
    );
  }

  if (relationship) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(name)} is a relationship in ${entityType} - only attributes can be filtered`,
    );
  }

  const known = names.map((known) => `:${known}`).join(", ");

  Interpreter.raiseArgumentError(
    `unknown attribute ${Interpreter.inspect(name)} in ${entityType} - known attributes: ${known}`,
  );
}

// A comparison operand on an enum is one of the values it declares, refused where it is written
// rather than where it is run: the database refuses an undeclared label too, but only once the
// statement reaches it, and by then nothing can name the values there were to choose from.
function validateEnumOperand(name, operand, entityType) {
  if (attributeType(entityType, name.value) !== "enum") {
    return;
  }

  const values = Model.entry(entityType).enumValues[name.value];

  if (!values.includes(Model.unbox(operand, "enum"))) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(operand)} is not a value of attribute ${Interpreter.inspect(name)} in ${entityType} - the values are ${inspectEnumValues(values)}`,
    );
  }
}

function validateMembershipList(operand, name, operator) {
  if (!Type.isList(operand)) {
    Interpreter.raiseArgumentError(
      `operator :${operator} on attribute ${Interpreter.inspect(name)} requires a list operand, got: ${Interpreter.inspect(operand)}`,
    );
  }

  if (operand.data.length === 0) {
    Interpreter.raiseArgumentError(
      `membership list for attribute ${Interpreter.inspect(name)} must not be empty`,
    );
  }

  operand.data.forEach((value) => {
    if (Type.isList(value) || Type.isTuple(value) || isStruct(value, "Range")) {
      Interpreter.raiseArgumentError(
        `invalid membership list element ${Interpreter.inspect(value)} for attribute ${Interpreter.inspect(name)} - membership lists hold plain values`,
      );
    }
  });
}

function validateMembershipRange(range, name, entityType) {
  const type = attributeType(entityType, name.value);

  if (type !== "integer") {
    Interpreter.raiseArgumentError(
      `range ${Interpreter.inspect(range)} requires an integer attribute - attribute ${Interpreter.inspect(name)} in ${entityType} has type :${type}`,
    );
  }

  if (field(range, "step").value !== 1n) {
    Interpreter.raiseArgumentError(
      `stepped range ${Interpreter.inspect(range)} for attribute ${Interpreter.inspect(name)} is not supported - membership ranges use step 1`,
    );
  }

  if (field(range, "last").value < field(range, "first").value) {
    Interpreter.raiseArgumentError(
      `range ${Interpreter.inspect(range)} for attribute ${Interpreter.inspect(name)} is empty - it would match nothing`,
    );
  }
}

// The types an ordering line can be drawn through: every type but boolean and uuid has an order
// to compare by. An enum's is the list it declares, on every tier. A string's is the same derived
// key its ordering uses, which the kernel reads off the row.
function validateOrderableAttribute(name, entityType, operator) {
  const type = attributeType(entityType, name.value);

  if (!ORDERABLE_TYPES.includes(type)) {
    Interpreter.raiseArgumentError(
      `operator :${operator} requires an orderable attribute - attribute ${Interpreter.inspect(name)} in ${entityType} has type :${type}, and boolean and uuid attributes have no order to compare by`,
    );
  }
}

function validateRelationshipName(name, entityType) {
  const relationship = Model.entry(entityType).relationships[name.value];

  if (relationship) {
    return {
      kind: relationship.toMany ? "to_many" : "to_one",
      target: relationship.type,
    };
  }

  if (attributeNames(entityType).includes(name.value)) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(name)} is an attribute in ${entityType} - only relationships can be included`,
    );
  }

  const known = relationshipNames(entityType)
    .map((relationshipName) => `:${relationshipName}`)
    .join(", ");

  Interpreter.raiseArgumentError(
    `unknown relationship ${Interpreter.inspect(name)} in ${entityType} - known relationships: ${known}`,
  );
}

function validateScalarOperand(name, operator, operand, refuseNil = false) {
  const invalid =
    Type.isList(operand) ||
    Type.isTuple(operand) ||
    isStruct(operand, "Range") ||
    (refuseNil && Type.isNil(operand));

  if (invalid) {
    Interpreter.raiseArgumentError(
      `invalid operand ${Interpreter.inspect(operand)} for operator :${operator} on attribute ${Interpreter.inspect(name)}`,
    );
  }
}

// A to-one embeds one entity, so there is nothing for a filter, an order or a bound to do to it -
// nesting is its only refinement, and two levels is as deep as either tier traverses.
function validateSubTerm(subTerm, name, target, kind) {
  if (!isQueryTerm(subTerm)) {
    Interpreter.raiseArgumentError(
      `include sub-builder for relationship ${Interpreter.inspect(name)} must return a query term for ${target}, got: ${Interpreter.inspect(subTerm)}`,
    );
  }

  if (subTerm.entity !== target) {
    Interpreter.raiseArgumentError(
      `include sub-builder for relationship ${Interpreter.inspect(name)} must return a query term for ${target} - got a query term for ${subTerm.entity}`,
    );
  }

  if (subTerm.cardinality !== "set") {
    Interpreter.raiseArgumentError(
      "include sub-terms take no cardinality marker - the relationship declaration governs cardinality",
    );
  }

  if (kind === "to_one" && subTermHasClauses(subTerm)) {
    Interpreter.raiseArgumentError(
      `to-one relationship ${Interpreter.inspect(name)} takes no clauses - clauses apply to to-many includes`,
    );
  }

  if (includeDepth(subTerm) > 1) {
    Interpreter.raiseArgumentError(
      `including ${Interpreter.inspect(name)} exceeds the traversal depth limit of 2 levels`,
    );
  }
}

function validateAmount(amount, stage) {
  if (Type.isInteger(amount) && (stage === "increment" || amount.value > 0n)) {
    return;
  }

  Interpreter.raiseArgumentError(
    stage === "increment"
      ? `increment takes an integer amount, got: ${Interpreter.inspect(amount)}`
      : `decrement takes a positive integer amount, got: ${Interpreter.inspect(amount)}`,
  );
}

function validateDeltaName(name, entityType, stage) {
  const counters = counterAttributeNames(entityType);
  const named = Type.isAtom(name) ? name.value : null;

  if (named !== null && counters.includes(named)) {
    return;
  }

  const spelled = Interpreter.inspect(name);

  if (named !== null && integerNames(entityType).includes(named)) {
    Interpreter.raiseArgumentError(
      `${spelled} in ${entityType} is optional and can hold nil - ${stage} moves attributes that always hold a number - declare it without optional: true, with a default`,
    );
  }

  if (named !== null && systemAttributeNames(entityType).includes(named)) {
    Interpreter.raiseArgumentError(
      `${spelled} is a system attribute of ${entityType} - it is managed automatically and can't be moved`,
    );
  }

  if (named !== null && attributeNames(entityType).includes(named)) {
    Interpreter.raiseArgumentError(
      `${spelled} is a :${attributeType(entityType, named)} attribute of ${entityType} - ${stage} moves integer attributes only`,
    );
  }

  if (named !== null && relationshipNames(entityType).includes(named)) {
    Interpreter.raiseArgumentError(
      `${spelled} is a relationship in ${entityType} - ${stage} moves integer attributes only`,
    );
  }

  const known = counters.map((counter) => `:${counter}`).join(", ");

  Interpreter.raiseArgumentError(
    `unknown attribute ${spelled} in ${entityType} - known counters: ${known}`,
  );
}

function validateEdgeRelationshipName(name, entityType) {
  const toManyNames = toManyRelationshipNames(entityType);
  const named = Type.isAtom(name) ? name.value : null;

  if (named !== null && toManyNames.includes(named)) {
    return;
  }

  const spelled = Interpreter.inspect(name);

  if (named !== null && toOneRelationshipNames(entityType).includes(named)) {
    Interpreter.raiseArgumentError(
      `${spelled} is a to-one relationship in ${entityType} - only to-many relationships hold edges - set its reference via put_attribute(:${named}_id, id)`,
    );
  }

  if (named !== null && attributeNames(entityType).includes(named)) {
    Interpreter.raiseArgumentError(
      `${spelled} is an attribute in ${entityType} - only to-many relationships hold edges - put it via put_attribute`,
    );
  }

  const known = toManyNames.map((toMany) => `:${toMany}`).join(", ");

  Interpreter.raiseArgumentError(
    `unknown relationship ${spelled} in ${entityType} - known to-many relationships: ${known}`,
  );
}

function validatePutName(name, entityType) {
  const settable = settableNames(entityType);
  const named = Type.isAtom(name) ? name.value : null;

  if (named !== null && settable.includes(named)) {
    return;
  }

  const spelled = Interpreter.inspect(name);

  if (named !== null && toOneRelationshipNames(entityType).includes(named)) {
    Interpreter.raiseArgumentError(
      `${spelled} is a relationship in ${entityType} - only attributes can be put - set its reference via :${named}_id`,
    );
  }

  if (named !== null && relationshipNames(entityType).includes(named)) {
    Interpreter.raiseArgumentError(
      `${spelled} is a relationship in ${entityType} - only attributes can be put - add its edges via add_relationship`,
    );
  }

  if (named !== null && systemAttributeNames(entityType).includes(named)) {
    Interpreter.raiseArgumentError(
      `${spelled} is a system attribute of ${entityType} - it is managed automatically and can't be put`,
    );
  }

  const known = settable.map((settableName) => `:${settableName}`).join(", ");

  Interpreter.raiseArgumentError(
    `unknown attribute ${spelled} in ${entityType} - known attributes: ${known}`,
  );
}

const Elixir_Hologram_Query = {
  "add_relationship/3": (entity, relationshipName, targetId) =>
    putRelationshipOp(
      entity,
      relationshipName,
      targetId,
      "add",
      "add_relationship",
    ),

  "authorize/2": (entity, operation) => {
    if (!Type.isAtom(operation)) {
      Interpreter.raiseArgumentError(
        `authorize takes an operation atom, got: ${Interpreter.inspect(operation)}`,
      );
    }

    return putClaim(
      entity,
      Type.tuple([Type.atom("authorize"), operation]),
      "authorize",
    );
  },

  "count/1": (query) => setCardinality(query, "count"),

  "decrement/3": (entity, name, amount) =>
    putDelta(entity, name, amount, -1, "decrement"),

  "delete_relationship/3": (entity, relationshipName, targetId) =>
    putRelationshipOp(
      entity,
      relationshipName,
      targetId,
      "delete",
      "delete_relationship",
    ),

  "filter/2": (query, predicates) => {
    const term = toTerm(query);

    if (!Type.isKeywordList(predicates)) {
      Interpreter.raiseArgumentError(
        `filter predicates must be a keyword list, got: ${Interpreter.inspect(predicates)}`,
      );
    }

    const triples = predicates.data.flatMap((pair) => {
      const [name, value] = pair.data;

      validateFilteredName(name, term.entity);

      return predicateTriples(name, value, term.entity);
    });

    return {...term, filter: [...term.filter, ...triples]};
  },
  "include/2": (query, spec) =>
    Elixir_Hologram_Query["include/3"](query, spec, Type.nil()),

  "include/3": (query, spec, subBuilder) => {
    if (Type.isAtom(spec)) {
      if (Type.isNil(subBuilder)) {
        return includeOne(query, spec, null);
      }

      if (Type.isAnonymousFunction(subBuilder) && subBuilder.arity === 1) {
        return includeOne(query, spec, subBuilder);
      }

      Interpreter.raiseArgumentError(
        `include sub-builder for relationship ${Interpreter.inspect(spec)} must be a one-argument function, got: ${Interpreter.inspect(subBuilder)}`,
      );
    }

    if (Type.isList(spec)) {
      if (!Type.isNil(subBuilder)) {
        Interpreter.raiseArgumentError(
          "an include shape spec takes no separate sub-builder - nest it in the spec as a {name, sub_builder} pair",
        );
      }

      if (spec.data.length === 0) {
        Interpreter.raiseArgumentError("include spec must not be empty");
      }

      return spec.data.reduce(includeSpecEntry, toTerm(query));
    }

    Interpreter.raiseArgumentError(
      `include spec must be a relationship name or a shape list, got: ${Interpreter.inspect(spec)}`,
    );
  },

  "increment/3": (entity, name, amount) =>
    putDelta(entity, name, amount, 1, "increment"),

  "limit/2": (query, value) => setViewBound(query, "limit", value),

  // The canonical form of a query - what the kernel runs literally.
  "normalize/1": (query) => normalizedTerm(toTerm(query)),

  "offset/2": (query, value) => setViewBound(query, "offset", value),
  "one/1": (query) => setCardinality(query, "one"),

  "order_by/2": (query, spec) => {
    const term = toTerm(query);

    return {...term, orderBy: orderEntries(spec, term.entity)};
  },

  "put_attribute/2": (entity, values) => {
    const entityType = entityTypeOf(entity, "put_attribute");
    const pairs = putPairs(values, "put_attribute");

    for (const [name] of pairs) {
      validatePutName(name, entityType);
    }

    return putAttributes(entity, pairs);
  },

  "put_attribute/3": (entity, name, value) =>
    Elixir_Hologram_Query["put_attribute/2"](
      entity,
      Type.list([Type.tuple([name, value])]),
    ),

  // Both forms the server accepts - an entity struct and a query - are refused here, in the wire's
  // own words. Trust is the SERVER's authority: a batch claiming it is refused by name, and a read
  // claiming it would be asking this client's copy of the data to answer past the policies that
  // decided what it holds. A helper reaching for it learns at its own line that it is server code.
  "trust/1": (_subject) => {
    Interpreter.raiseArgumentError(
      "trust is the server's authority - a client cannot claim it",
    );
  },
};

export default Elixir_Hologram_Query;
