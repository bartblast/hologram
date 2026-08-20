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
const ORDERABLE_TYPES = ["date", "datetime", "float", "integer"];
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

function orderEntry(entry, entityType) {
  if (Type.isAtom(entry)) {
    validateOrderedAttribute(entry, entityType);

    return [entry.value, "asc"];
  }

  if (
    Type.isTuple(entry) &&
    entry.data.length === 2 &&
    Type.isAtom(entry.data[0])
  ) {
    const [name, direction] = entry.data;

    validateOrderedAttribute(name, entityType);

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
  const relationships = Model.entry(entityType).relationships;

  const references = Object.entries(relationships)
    .filter(([_name, relationship]) => !relationship.toMany)
    .map(([name]) => `${name}_id`);

  return [...attributeNames(entityType), ...references].sort();
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
    isStruct(value, "Hologram.Query.Param")
      ? paramLeaf(value)
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

  if (isStruct(operand, "Hologram.Query.Param")) {
    if (ORDERING_OPERATORS.includes(operator)) {
      validateOrderableAttribute(name, entityType, operator);
    } else if (
      !EQUALITY_OPERATORS.includes(operator) &&
      !MEMBERSHIP_OPERATORS.includes(operator)
    ) {
      raiseUnknownOperator(operator, name);
    }

    return [[name.value, operator, paramLeaf(operand)]];
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

function paramLeaf(param) {
  return {param: field(param, "name").value};
}

// Every shape a predicate value can take, dispatched in the order the Elixir clauses are written
// in - the shapes that are structures (a range, a param, the actor) before the general tuple, and
// the general tuple before the plain value a bare term falls through to.
function predicateTriples(name, value, entityType) {
  if (isStruct(value, "Range")) {
    return rangeTriples(name, value, entityType);
  }

  if (isStruct(value, "Hologram.Query.Param")) {
    return [[name.value, "==", paramLeaf(value)]];
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

  if (term[field] !== null) {
    Interpreter.raiseArgumentError(`${field} is already set to ${term[field]}`);
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

// The types an ordering line can be drawn through: strings are excluded because byte order is
// the same on both tiers but wrong for people, and the key that fixes that belongs to ordering.
function validateOrderableAttribute(name, entityType, operator) {
  const type = attributeType(entityType, name.value);

  if (!ORDERABLE_TYPES.includes(type)) {
    Interpreter.raiseArgumentError(
      `operator :${operator} requires a numeric or temporal attribute - attribute ${Interpreter.inspect(name)} in ${entityType} has type :${type}`,
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

// The two tiers disagree on what order enum values are in - the database orders them by
// declaration, this side would order them by their labels - so neither orders by them.
function validateOrderedAttribute(name, entityType) {
  validateAttributeName(name, entityType, "ordered");

  if (attributeType(entityType, name.value) === "enum") {
    Interpreter.raiseArgumentError(
      `ordering by enum attributes is not supported - attribute ${Interpreter.inspect(name)} in ${entityType} has type :enum`,
    );
  }
}

const Elixir_Hologram_Query = {
  "count/1": (query) => setCardinality(query, "count"),

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

  "limit/2": (query, value) => setViewBound(query, "limit", value),

  // The canonical form of a query - what the kernel runs literally.
  "normalize/1": (query) => normalizedTerm(toTerm(query)),

  "offset/2": (query, value) => setViewBound(query, "offset", value),
  "one/1": (query) => setCardinality(query, "one"),

  "order_by/2": (query, spec) => {
    const term = toTerm(query);

    return {...term, orderBy: orderEntries(spec, term.entity)};
  },
};

export default Elixir_Hologram_Query;
