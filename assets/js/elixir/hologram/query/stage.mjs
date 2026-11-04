"use strict";

import Interpreter from "../../../interpreter.mjs";
import Model from "../../../model.mjs";
import Type from "../../../type.mjs";

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
// mirrored, and the unit tests of both tiers pin the same words.

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
const QUANTIFIERS = ["all", "any", "none"];
const SEARCH_OPERATORS = [
  "contains",
  "contains_exact",
  "starts_with",
  "starts_with_exact",
];

// The type pairs whose attributes compare though their types differ, compared on the wider type -
// Hologram.Query.Stage's @widenings, and the two must agree.
const WIDENINGS = [
  ["float", "integer"],
  ["integer", "float"],
];

// The names an attribute may be ordered or read by - declared and system alike, sorted, the way
// the model bakes them. Reference fields are deliberately absent, as they are on the server: a
// relationship is followed, not ordered by.
function attributeNames(entityType) {
  return Object.keys(Model.entry(entityType).attributes);
}

// Another attribute as a predicate's operand, checked the way the server checks it - an ordering
// comparison needs an orderable attribute, the other one has to be filterable, and the two have to
// compare. Inside a quantifier the two can live on two rows, so each is looked up where it lives.
function attributeTriple(name, operator, other, entityType, scope) {
  if (ORDERING_OPERATORS.includes(operator)) {
    validateOrderableAttribute(name, entityType, operator);
  }

  if (SEARCH_OPERATORS.includes(operator)) {
    validateSearchableAttribute(name, entityType, operator);
  }

  const otherType = nameTypeOf(scope, other);

  validateOperandName(other, otherType);
  validateComparableAttributes(name, other, operator, entityType, otherType);

  // Two compared attributes share a type, so the operand is orderable or searchable when the name
  // is - unless it is a derived string, which has no stored sort key or search forms.
  if (ORDERING_OPERATORS.includes(operator)) {
    validateOrderableAttribute(other, otherType, operator);
  }

  if (SEARCH_OPERATORS.includes(operator)) {
    validateSearchableAttribute(other, otherType, operator);
  }

  return [nameValue(name), operator, {attribute: nameValue(other)}];
}

// A name matching no attribute definition is a derived field holding a value, typed as declared,
// or else a to-one reference field, which carries an entity id - the fallback both tiers make.
function attributeType(entityType, name) {
  const derived = Model.derivedField(entityType, name);
  const derivedType = derived?.kind === "scalar" ? derived.type : null;

  return Model.entry(entityType).attributes[name] ?? derivedType ?? "uuid";
}

function byKey(keyOf) {
  return (left, right) => {
    const [leftKey, rightKey] = [keyOf(left), keyOf(right)];

    return leftKey < rightKey ? -1 : leftKey > rightKey ? 1 : 0;
  };
}

function clauseKey(clause) {
  if ("quantifier" in clause) {
    return [
      clause.quantifier,
      JSON.stringify([clause.source, clause.filter]),
    ].join("\u0000");
  }

  if (Array.isArray(clause)) {
    const [name, operator, operand] = clause;
    const spelledName = typeof name === "string" ? name : JSON.stringify(name);

    return [spelledName, operator, JSON.stringify(operand ?? null)].join(
      "\u0000",
    );
  }

  return ["or", JSON.stringify(clause.or)].join("\u0000");
}

// A counter is an integer attribute that always holds a number: an optional one can be nil, and
// there is nothing to add to nil.
function counterAttributeNames(entityType) {
  const constraints = Model.entry(entityType).constraints;

  return integerNames(entityType).filter(
    (name) => constraints[name]?.optional !== true,
  );
}

// The order a set relationship declares, stored or inverse - none for a name that is no set.
function declaredOrder(entityType, name) {
  const relationships = Model.relationships(entityType);
  const inverses = Model.inverses(entityType);

  if (Object.hasOwn(relationships, name)) {
    return relationships[name].sort ?? [];
  }

  return Object.hasOwn(inverses, name) ? inverses[name].sort : [];
}

// The derived field of the given name holding rows - one or a set - or null for any other name.
function derivedRows(entityType, name) {
  const derived = Model.derivedField(entityType, name);

  return derived && derived.kind !== "scalar" ? derived : null;
}

// What a derived field holds, as a message names it: one row or a set of them.
function derivedRowsSpelled(derived) {
  return derived.kind === "set" ? "a set of rows" : "one row";
}

// The element type of the derived set of the given name, refusing a derived field that holds no
// set with the given reason, null for a name that is no derived field.
function derivedSetTarget(name, entityType, reason) {
  const derived = Model.derivedField(entityType, name.value);

  if (!derived) {
    return null;
  }

  if (derived.kind === "set") {
    return derived.entity;
  }

  const held =
    derived.kind === "one"
      ? derivedRowsSpelled(derived)
      : `a :${derived.type} value`;

  Interpreter.raiseArgumentError(
    `${Interpreter.inspect(name)} is a derived field holding ${held} in ${entityType} - ${reason}`,
  );
}

// The derived fields holding a value of an attribute type, by name, with the type each declares.
function derivedValueTypes(entityType) {
  return Object.fromEntries(
    Object.entries(Model.derived(entityType))
      .filter(([_name, derived]) => derived.kind === "scalar")
      .map(([name, derived]) => [name, derived.type]),
  );
}

// One alternative says what its predicates say alone, and an empty one says nothing at all - it
// would make the disjunction hold for every row - so neither is a disjunction, as on the server.
function disjunctionClause(alternatives, scope) {
  if (alternatives.data.length < 2) {
    Interpreter.raiseArgumentError(
      `a disjunction takes a list of at least two predicate lists, got: ${Interpreter.inspect(alternatives)}`,
    );
  }

  for (const alternative of alternatives.data) {
    if (!isPredicateList(alternative) || alternative.data.length === 0) {
      Interpreter.raiseArgumentError(
        `an alternative of a disjunction is a non-empty list of name and value pairs, got: ${Interpreter.inspect(alternative)}`,
      );
    }
  }

  return {
    or: alternatives.data.map((alternative) =>
      alternative.data.flatMap((pair) => entryClauses(pair, scope)),
    ),
  };
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

// The shape decides rather than the name, so or is no reserved attribute name: a list of lists is
// no value any attribute takes, and an attribute named or keeps every other spelling. The same goes
// for the quantifiers: a pair whose first element is a list or an outer tuple is no operator tuple.
//
// The scope is the type of the row the predicates are about, then the type of each row above it,
// nearest first - the queried type last.
function entryClauses(pair, scope) {
  const [name, value] = pair.data;

  if (
    Type.isAtom(name) &&
    name.value === "or" &&
    Type.isList(value) &&
    value.data.every(Type.isList)
  ) {
    return [disjunctionClause(value, scope)];
  }

  if (
    Type.isAtom(name) &&
    QUANTIFIERS.includes(name.value) &&
    isQuantifierValue(value)
  ) {
    return [quantifierClause(scope, name.value, value)];
  }

  const entityType = nameTypeOf(scope, name);
  const declaredName = localName(name);

  if (isPath(declaredName)) {
    validatePath(declaredName, entityType);
  } else {
    validateFilteredName(declaredName, entityType);
  }

  return predicateTriples(name, value, entityType, scope);
}

// The values an enum declares, in their declared order: an enum attribute's, or a derived enum's.
function enumValues(entityType, name) {
  return (
    Model.entry(entityType).enumValues[name] ??
    Model.derivedField(entityType, name).values
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
    `sort spec must be an attribute name or a list, got: ${Interpreter.inspect(spec)}`,
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
    `invalid sort entry ${Interpreter.inspect(entry)} - use an attribute name or an {attribute, :asc | :desc} tuple`,
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
    ...Object.keys(derivedValueTypes(entityType)),
  ].sort();
}

// A derived field holding a value is included with nothing under it, as null. Any other name is
// included as its related type's whole term, what the nested spec names included under it - a
// derived field holding rows takes nested includes only, since its definition states its rows.
function includeOne(query, name, nestedSpec) {
  const term = toTerm(query);
  const {kind, target} = validateIncludedName(name, term.entity);

  if (kind === "derived_value") {
    if (nestedSpec !== null) {
      Interpreter.raiseArgumentError(
        `${Interpreter.inspect(name)} is a :${target} derived field in ${term.entity} - nothing is included under it`,
      );
    }

    return {...term, include: putIncluded(term.include, name.value, null)};
  }

  const relatedBaseTerm = toTerm(Type.alias(target));

  const subTerm =
    nestedSpec === null
      ? relatedBaseTerm
      : Elixir_Hologram_Query_Stage["include/2"](relatedBaseTerm, nestedSpec);

  return {...term, include: putIncluded(term.include, name.value, subTerm)};
}

// A spec entry is a relationship name or a {name, nested spec} pair. A function would narrow the
// set, which is what a derived field does - refused naming one.
function includeSpecEntry(term, entry) {
  if (Type.isAtom(entry)) {
    return includeOne(term, entry, null);
  }

  if (isConstraintTuple(entry)) {
    const [name, spec] = entry.data;

    if (Type.isAnonymousFunction(spec)) {
      Interpreter.raiseArgumentError(
        `invalid include spec entry ${Interpreter.inspect(entry)} - include takes names and paths - a narrowed, ordered or bounded set is a derived field: derived :open_tasks, [Task], fn tasks -> filter(tasks, ...) end`,
      );
    }

    return includeOne(term, name, spec);
  }

  Interpreter.raiseArgumentError(
    `invalid include spec entry ${Interpreter.inspect(entry)} - use a relationship name or a {name, spec} pair`,
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

// A name as a refusal spells it: an attribute as the interpreter inspects it, a path as it is
// written.
function inspectName(name) {
  if (isOuterName(name)) {
    return inspectName(name.data[2]);
  }

  return isPath(name)
    ? name.data.map((atom) => atom.value).join(".")
    : Interpreter.inspect(name);
}

// The {:actor} leaf user_id() lowers to - bare, or as the operand of an equality operator.
function isActorLeaf(value) {
  return (
    Type.isTuple(value) &&
    value.data.length === 1 &&
    Type.isAtom(value.data[0]) &&
    value.data[0].value === "actor"
  );
}

// The {:attribute, name} tuple a bare name or a path on the right side of a comparison lowers to -
// the name, inside a quantifier, possibly one of a row above.
function isAttributeOperand(value) {
  return (
    Type.isTuple(value) &&
    value.data.length === 2 &&
    Type.isAtom(value.data[0]) &&
    value.data[0].value === "attribute" &&
    (Type.isAtom(value.data[1]) ||
      Type.isList(value.data[1]) ||
      isOuterTuple(value.data[1]))
  );
}

// A two-element tuple led by an atom - what an operator predicate looks like, and what tells a
// list of them from a list of plain values.
function isConstraintTuple(value) {
  return (
    Type.isTuple(value) && value.data.length === 2 && Type.isAtom(value.data[0])
  );
}

// Whether a name is a derived string: a computed string has no stored sort key or folded form, so
// it is not ordered or searched.
function isDerivedString(entityType, name) {
  const declared = subject(entityType, name);
  const derived = Model.derivedField(declared.entityType, declared.name);

  return derived?.kind === "scalar" && derived.type === "string";
}

// {:outer, levels, name} with an integer number of levels and an attribute or a path as the name -
// a name of the row that many quantifiers out.
function isOuterName(value) {
  return (
    isOuterTuple(value) &&
    Type.isInteger(value.data[1]) &&
    (Type.isAtom(value.data[2]) || isPath(value.data[2]))
  );
}

// A three-element tuple led by :outer, whatever it holds after.
function isOuterTuple(value) {
  return (
    Type.isTuple(value) &&
    value.data.length === 3 &&
    Type.isAtom(value.data[0]) &&
    value.data[0].value === "outer"
  );
}

// Two or more names: the to-one relationships followed from the queried type, then an attribute of
// the row they lead to.
function isPath(name) {
  return (
    Type.isList(name) && name.data.length >= 2 && name.data.every(Type.isAtom)
  );
}

function isPlainValue(value) {
  return (
    !Type.isTuple(value) && !Type.isList(value) && !isStruct(value, "Range")
  );
}

// A list pairing names - attributes, paths, or names of a row above - with predicate values, the
// data form a filter takes.
function isPredicateList(value) {
  return (
    Type.isList(value) &&
    value.data.every(
      (entry) =>
        Type.isTuple(entry) &&
        entry.data.length === 2 &&
        (Type.isAtom(entry.data[0]) ||
          isPath(entry.data[0]) ||
          isOuterName(entry.data[0])),
    )
  );
}

// A quantifier's {source, predicates} pair - the source a list or an outer tuple.
function isQuantifierValue(value) {
  return (
    Type.isTuple(value) &&
    value.data.length === 2 &&
    Type.isList(value.data[1]) &&
    (Type.isList(value.data[0]) || isOuterTuple(value.data[0]))
  );
}

// A stage returns the plain term this file builds, so a query handed to a stage is told from
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
function listTriples(name, list, entityType, scope) {
  const values = list.data;

  if (values.length === 0) {
    Interpreter.raiseArgumentError(
      `filter list for attribute ${inspectName(name)} must not be empty`,
    );
  }

  if (values.every(isConstraintTuple)) {
    return values.flatMap((value) =>
      predicateTriples(name, value, entityType, scope),
    );
  }

  if (values.every(isPlainValue)) {
    validateMembershipList(list, name, "in");

    return [
      [nameValue(name), "in", membershipValues(values, name, entityType)],
    ];
  }

  Interpreter.raiseArgumentError(
    `invalid filter list ${Interpreter.inspect(list)} for attribute ${inspectName(name)} - use either a membership list of plain values or a list of operator tuples`,
  );
}

// A name as the row it lives on declares it - an attribute or a path - whichever row that is.
function localName(name) {
  return isOuterTuple(name) ? name.data[2] : name;
}

function membershipValues(values, name, entityType) {
  return values.map((value) =>
    isStruct(value, "Hologram.Query.Placeholder")
      ? placeholderLeaf(value)
      : Model.unbox(value, nameType(entityType, name)),
  );
}

// Two includes of one relationship are one include: what each includes merges, by the same rule
// all the way down.
function mergedSubTerm(included, subTerm) {
  if (included === null && subTerm === null) {
    return null;
  }

  const include = Object.entries(subTerm.include).reduce(
    (acc, [nestedName, nestedSubTerm]) =>
      putIncluded(acc, nestedName, nestedSubTerm),
    included.include,
  );

  return {...included, include};
}

// The type of what a name reads: an attribute's, or the one a path ends at.
function nameType(entityType, name) {
  const declared = subject(entityType, name);

  return attributeType(declared.entityType, declared.name);
}

// The type a name is declared on: the row the clauses are about, or for {:outer, levels, name} the
// row that many quantifiers out, which the scope holds after it.
function nameTypeOf(scope, name) {
  if (!isOuterTuple(name)) {
    return scope[0];
  }

  const levelsTerm = name.data[1];
  const rowsAbove = scope.length - 1;

  const levels = Type.isInteger(levelsTerm) ? Number(levelsTerm.value) : null;

  if (levels === null || levels < 1 || levels > rowsAbove) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(name)} names no row above the condition it stands in, which has ${rowsSpelled(rowsAbove)} above it - {:outer, levels, name} reads the row levels quantifiers out, from 1 up to the outermost row`,
    );
  }

  return scope[levels];
}

// A name as a triple spells it: an attribute's name, a path's names in order, or a name of a row
// above with how many quantifiers out it lies.
function nameValue(name) {
  if (isOuterTuple(name)) {
    return {outer: Number(name.data[1].value), name: nameValue(name.data[2])};
  }

  return isPath(name) ? name.data.map((atom) => atom.value) : name.value;
}

// A to-one embeds one row, and a derived field's rows are the ones its definition states, so
// neither carries an order of its own - only what it includes is normalized.
function normalizedIncludes(term) {
  return Object.fromEntries(
    Object.entries(term.include).map(([name, subTerm]) => {
      if (subTerm === null) {
        return [name, null];
      }

      const {kind} = validateIncludedName(Type.atom(name), term.entity);
      const orderedSubTerm = withDeclaredOrder(subTerm, term.entity, name);

      return [
        name,
        kind === "to_many"
          ? normalizedTerm(orderedSubTerm)
          : {...orderedSubTerm, include: normalizedIncludes(orderedSubTerm)},
      ];
    }),
  );
}

function normalizedOrder(term) {
  if (term.cardinality === "count") {
    return [];
  }

  return term.sort.some(([name]) => name === "id")
    ? term.sort
    : [...term.sort, ["id", "asc"]];
}

function normalizedTerm(term) {
  return {
    ...term,
    filter: sortedFilter(term.filter),
    include: normalizedIncludes(term),
    sort: normalizedOrder(term),
  };
}

function operatorTriples(name, tuple, entityType, scope) {
  const [operatorAtom, operand] = tuple.data;
  const operator = operatorAtom.value;

  if (isStruct(operand, "Range") && operator === "in") {
    return rangeTriples(name, operand, entityType);
  }

  if (isStruct(operand, "Hologram.Query.Placeholder")) {
    if (ORDERING_OPERATORS.includes(operator)) {
      validateOrderableAttribute(name, entityType, operator);
    } else if (SEARCH_OPERATORS.includes(operator)) {
      validateSearchableAttribute(name, entityType, operator);
    } else if (
      !EQUALITY_OPERATORS.includes(operator) &&
      !MEMBERSHIP_OPERATORS.includes(operator)
    ) {
      raiseUnknownOperator(operator, name);
    }

    return [[nameValue(name), operator, placeholderLeaf(operand)]];
  }

  if (
    isAttributeOperand(operand) &&
    (EQUALITY_OPERATORS.includes(operator) ||
      ORDERING_OPERATORS.includes(operator) ||
      SEARCH_OPERATORS.includes(operator))
  ) {
    return [
      attributeTriple(name, operator, operand.data[1], entityType, scope),
    ];
  }

  if (EQUALITY_OPERATORS.includes(operator) && isActorLeaf(operand)) {
    validateActorAttribute(name, entityType);

    return [[nameValue(name), operator, {actor: true}]];
  }

  if (EQUALITY_OPERATORS.includes(operator)) {
    validateScalarOperand(name, operator, operand);

    return [
      [
        nameValue(name),
        operator,
        Model.unbox(operand, nameType(entityType, name)),
      ],
    ];
  }

  if (MEMBERSHIP_OPERATORS.includes(operator)) {
    validateMembershipList(operand, name, operator);

    return [
      [
        nameValue(name),
        operator,
        membershipValues(operand.data, name, entityType),
      ],
    ];
  }

  if (ORDERING_OPERATORS.includes(operator)) {
    validateOrderableAttribute(name, entityType, operator);
    validateScalarOperand(name, operator, operand, true);
    validateEnumOperand(name, operand, entityType);

    return [
      [
        nameValue(name),
        operator,
        Model.unbox(operand, nameType(entityType, name)),
      ],
    ];
  }

  if (SEARCH_OPERATORS.includes(operator)) {
    return [searchTriple(name, operator, operand, entityType)];
  }

  raiseUnknownOperator(operator, name);
}

function placeholderLeaf(placeholder) {
  return {placeholder: field(placeholder, "name").value};
}

// Every shape a predicate value can take, dispatched in the order the Elixir clauses are written
// in - the shapes that are structures (a range, a placeholder, the actor) before the general tuple, and
// the general tuple before the plain value a bare term falls through to.
function predicateTriples(name, value, entityType, scope) {
  if (isStruct(value, "Range")) {
    return rangeTriples(name, value, entityType);
  }

  if (isStruct(value, "Hologram.Query.Placeholder")) {
    return [[nameValue(name), "==", placeholderLeaf(value)]];
  }

  if (isActorLeaf(value)) {
    validateActorAttribute(name, entityType);

    return [[nameValue(name), "==", {actor: true}]];
  }

  if (isAttributeOperand(value)) {
    return [attributeTriple(name, "==", value.data[1], entityType, scope)];
  }

  if (isConstraintTuple(value)) {
    return operatorTriples(name, value, entityType, scope);
  }

  if (Type.isTuple(value)) {
    Interpreter.raiseArgumentError(
      `invalid filter value ${Interpreter.inspect(value)} for attribute ${inspectName(name)}`,
    );
  }

  if (Type.isList(value)) {
    return listTriples(name, value, entityType, scope);
  }

  return [
    [nameValue(name), "==", Model.unbox(value, nameType(entityType, name))],
  ];
}

// The source decides the related type the predicates are about, and the rows above them stay in
// the scope, nearest first.
function quantifierClause(scope, quantifier, value) {
  const [source, predicates] = value.data;
  const {entityType: sourceType, hops} = sourceStart(scope, source);
  const relatedType = validateSource(hops, sourceType);

  if (!isPredicateList(predicates)) {
    Interpreter.raiseArgumentError(
      `a quantifier's condition is a list of name and value pairs, got: ${Interpreter.inspect(predicates)}`,
    );
  }

  if (quantifier === "all" && predicates.data.length === 0) {
    Interpreter.raiseArgumentError(
      `all takes a condition - all over no condition says nothing, got: ${Interpreter.inspect(value)}`,
    );
  }

  const innerScope = [relatedType, ...scope];

  return {
    filter: predicates.data.flatMap((pair) => entryClauses(pair, innerScope)),
    quantifier,
    source: sourceValue(source),
  };
}

function raiseUnknownOperator(operator, name) {
  Interpreter.raiseArgumentError(
    `unknown operator :${operator} in the filter predicate for attribute ${inspectName(name)} - supported operators: :!=, :<, :<=, :==, :>, :>=, :contains, :contains_exact, :in, :not_in, :starts_with, :starts_with_exact`,
  );
}

// The known relationships are every relationship of the type - a source takes any of them.
function raiseUnknownSourceName(name, entityType) {
  if (attributeNames(entityType).includes(name.value)) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(name)} is an attribute in ${entityType} - a quantifier's source names relationships`,
    );
  }

  const known = relationshipNames(entityType)
    .concat(Object.keys(Model.inverses(entityType)))
    .sort()
    .map((knownName) => `:${knownName}`)
    .join(", ");

  Interpreter.raiseArgumentError(
    `unknown relationship ${Interpreter.inspect(name)} in ${entityType} - known relationships: ${known}`,
  );
}

// A range is two bounds rather than a membership set - it says the same thing about an integer
// attribute in the words the two comparisons already have.
function rangeTriples(name, range, entityType) {
  validateMembershipRange(range, name, entityType);

  return [
    [nameValue(name), ">=", Number(field(range, "first").value)],
    [nameValue(name), "<=", Number(field(range, "last").value)],
  ];
}

function rowsSpelled(count) {
  if (count === 0) {
    return "no row";
  }

  return count === 1 ? "1 row" : `${count} rows`;
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

function referenceFieldNames(entityType) {
  return toOneRelationshipNames(entityType).map((name) => `${name}_id`);
}

// Where the write an inverse reads goes instead - Hologram.Query.Stage's inverse_write_fix/3.
function inverseWriteFix(entityType, name, stage) {
  const inverse = Model.inverses(entityType)[name];
  const row = `the ${inverse.type} row`;

  return inverse.reference
    ? `set that reference on ${row} via put_attribute(:${inverse.forward}_id, id)`
    : `record the edge on ${row} via ${stage}(:${inverse.forward}, id)`;
}

function relationshipNames(entityType) {
  return Object.keys(Model.entry(entityType).relationships);
}

// A search term is matched as text, so it is a string - a nil term has no text to look for, and a
// list, a range or a tuple is another operator's operand.
function searchTriple(name, operator, operand, entityType) {
  validateSearchableAttribute(name, entityType, operator);

  if (!Type.isBinary(operand)) {
    Interpreter.raiseArgumentError(
      `invalid operand ${Interpreter.inspect(operand)} for operator :${operator} on attribute ${inspectName(name)} - a search term is a string`,
    );
  }

  return [nameValue(name), operator, Model.unbox(operand, "string")];
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

function sortedClause(clause) {
  if (Array.isArray(clause)) {
    return clause;
  }

  if ("quantifier" in clause) {
    return {...clause, filter: sortedFilter(clause.filter)};
  }

  return {
    or: clause.or
      .map(sortedFilter)
      .sort(byKey((alternative) => JSON.stringify(alternative))),
  };
}

// Conjunction and disjunction are commutative, so the order predicates and alternatives were
// written in carries nothing - one canonical order, all the way down, is what makes two spellings
// of the same query the same term. What that is FOR is the server's: it hashes the normalized term
// into the query's content id, and two spellings hashing apart would register, cache and scope one
// query twice. The kernel here evaluates the clauses in any order, so this side is indifferent to
// it - it is sorted because normalize is one function, mirrored.
//
// The order itself is this tier's own, and cannot be the server's: the operands are already the
// wire spellings here ("2026-08-18") where the server holds Elixir values (~D[2026-08-18]), so
// ordering them by anything orders them differently. Nothing compares the two, and nothing may:
// a hash taken of a term on this side is NOT the server's content id for that query. If one is
// ever needed here, it comes from the server.
function sortedFilter(filter) {
  return filter.map(sortedClause).sort(byKey(clauseKey));
}

// Where a source starts: the row the quantifier is about, or for {:outer, levels, hops} the row
// that many quantifiers out.
function sourceStart(scope, source) {
  const hops = isOuterTuple(source) ? source.data[2] : source;

  if (
    !Type.isList(hops) ||
    hops.data.length === 0 ||
    !hops.data.every(Type.isAtom)
  ) {
    Interpreter.raiseArgumentError(
      `a quantifier's source is a list of relationship names, or {:outer, levels, list}, got: ${Interpreter.inspect(source)}`,
    );
  }

  return {entityType: nameTypeOf(scope, source), hops: hops.data};
}

// A source as the term spells it: its relationships in order, or those of a row above with how
// many quantifiers out it lies.
function sourceValue(source) {
  if (isOuterTuple(source)) {
    return {
      outer: Number(source.data[1].value),
      name: source.data[2].data.map((atom) => atom.value),
    };
  }

  return source.data.map((atom) => atom.value);
}

// Where a name is declared: an attribute on the queried type, a path's last name on the type its
// relationships lead to. The path is validated before anything asks.
function subject(entityType, name) {
  if (isOuterTuple(name)) {
    return subject(entityType, name.data[2]);
  }

  if (!isPath(name)) {
    return {entityType, name: name.value};
  }

  const names = name.data.map((atom) => atom.value);

  return {
    entityType: Model.pathTarget(entityType, names.slice(0, -1)),
    name: names[names.length - 1],
  };
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
    skip: null,
    sort: [],
    take: null,
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

    return Elixir_Hologram_Query_Stage["put_attribute/3"](
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

function putIncluded(include, name, subTerm) {
  return {
    ...include,
    [name]: Object.hasOwn(include, name)
      ? mergedSubTerm(include[name], subTerm)
      : subTerm,
  };
}

// The two edge stages share everything but the operation they record. The relationship's own
// field is left alone: an edge is recorded, not applied, and what the field holds is whatever the
// read put there.
function putRelationshipOp(entity, relationshipName, targetId, op, stage) {
  const entityType = entityTypeOf(entity, stage);

  validateEdgeRelationshipName(relationshipName, entityType, stage);

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
  const type = nameType(entityType, name);

  if (type !== "uuid") {
    Interpreter.raiseArgumentError(
      `user_id() requires a uuid attribute - attribute ${inspectName(name)} in ${entityType} has type :${type}`,
    );
  }
}

function validateAttributeName(name, entityType, usage) {
  const orderableDerivedNames = Object.entries(derivedValueTypes(entityType))
    .filter(([_name, type]) => type !== "string")
    .map(([derivedName]) => derivedName);

  const names = [
    ...attributeNames(entityType),
    ...orderableDerivedNames,
  ].sort();

  if (isDerivedString(entityType, name)) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(name)} is a derived string in ${entityType} - a string is ${usage} by the sort key stored with it, which a computed string has none of`,
    );
  }

  if (names.includes(name.value)) {
    return;
  }

  if (relationshipNames(entityType).includes(name.value)) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(name)} is a relationship in ${entityType} - only attributes can be ${usage}`,
    );
  }

  const derived = derivedRows(entityType, name.value);

  if (derived) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(name)} is a derived field holding ${derivedRowsSpelled(derived)} in ${entityType} - only attributes can be ${usage}`,
    );
  }

  const known = names.map((known) => `:${known}`).join(", ");

  Interpreter.raiseArgumentError(
    `unknown attribute ${Interpreter.inspect(name)} in ${entityType} - known attributes: ${known}`,
  );
}

// Two attributes compare on one order and one notion of equality, so their types have to agree -
// the same type, or a widening - and two enums have to declare the same values in the same order,
// since a comparison reads positions. An attribute compared with itself says nothing anyone means.
//
// The two names may live on two rows - inside a quantifier, the related row and one above it - so
// each is typed on its own row, and the same name on two rows is two attributes.
function validateComparableAttributes(
  name,
  other,
  operator,
  entityType,
  otherEntityType,
) {
  if (JSON.stringify(nameValue(name)) === JSON.stringify(nameValue(other))) {
    Interpreter.raiseArgumentError(
      `operator :${operator} compares attribute ${inspectName(name)} in ${entityType} with itself`,
    );
  }

  const type = nameType(entityType, name);
  const otherType = nameType(otherEntityType, other);

  const compared =
    entityType === otherEntityType
      ? `attribute ${inspectName(name)} with attribute ${inspectName(other)} in ${entityType}`
      : `attribute ${inspectName(name)} in ${entityType} with attribute ${inspectName(other)} in ${otherEntityType}`;

  const widens = WIDENINGS.some(
    ([from, to]) => from === type && to === otherType,
  );

  if (type !== otherType && !widens) {
    Interpreter.raiseArgumentError(
      `operator :${operator} compares ${compared}, which have different types (:${type} and :${otherType}) - two attributes compare when they have the same type, or when one widens to the other (:integer to :float)`,
    );
  }

  if (type !== "enum") {
    return;
  }

  const declared = subject(entityType, name);
  const otherDeclared = subject(otherEntityType, other);
  const values = enumValues(declared.entityType, declared.name);
  const otherValues = enumValues(otherDeclared.entityType, otherDeclared.name);

  const sameValues =
    values.length === otherValues.length &&
    values.every((value, index) => value === otherValues[index]);

  if (!sameValues) {
    Interpreter.raiseArgumentError(
      `operator :${operator} compares ${compared}, which declare different values (${inspectEnumValues(values)} and ${inspectEnumValues(otherValues)}) - two enum attributes compare only when they declare the same values in the same order`,
    );
  }
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

  if (relationship || Object.hasOwn(Model.inverses(entityType), name.value)) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(name)} is a relationship in ${entityType} - only attributes can be filtered`,
    );
  }

  const derived = derivedRows(entityType, name.value);

  if (derived) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(name)} is a derived field holding ${derivedRowsSpelled(derived)} in ${entityType} - only attributes can be filtered`,
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
  if (nameType(entityType, name) !== "enum") {
    return;
  }

  const declared = subject(entityType, name);
  const values = enumValues(declared.entityType, declared.name);

  if (!values.includes(Model.unbox(operand, "enum"))) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(operand)} is not a value of attribute ${inspectName(name)} in ${entityType} - the values are ${inspectEnumValues(values)}`,
    );
  }
}

// A stored relationship or an inverse - a set of either is included as a to-many, a single
// inverse as a to-one - or a derived field: one holding rows is included as its rows' type, one
// holding a value as its type.
function validateIncludedName(name, entityType) {
  const entry = Model.entry(entityType);

  const relationship = Object.hasOwn(entry.relationships, name.value)
    ? entry.relationships[name.value]
    : Object.hasOwn(entry.inverses, name.value)
      ? entry.inverses[name.value]
      : null;

  if (relationship) {
    return {
      kind: relationship.toMany ? "to_many" : "to_one",
      target: relationship.type,
    };
  }

  const derived = Model.derivedField(entityType, name.value);

  if (derived) {
    return derived.kind === "scalar"
      ? {kind: "derived_value", target: derived.type}
      : {kind: "derived_rows", target: derived.entity};
  }

  if (attributeNames(entityType).includes(name.value)) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(name)} is an attribute in ${entityType} - only relationships and derived fields can be included`,
    );
  }

  const known = relationshipNames(entityType)
    .concat(Object.keys(entry.inverses), Object.keys(entry.derived))
    .sort()
    .map((loadableName) => `:${loadableName}`)
    .join(", ");

  Interpreter.raiseArgumentError(
    `unknown relationship ${Interpreter.inspect(name)} in ${entityType} - known relationships and derived fields: ${known}`,
  );
}

function validateMembershipList(operand, name, operator) {
  if (!Type.isList(operand)) {
    Interpreter.raiseArgumentError(
      `operator :${operator} on attribute ${inspectName(name)} requires a list operand, got: ${Interpreter.inspect(operand)}`,
    );
  }

  if (operand.data.length === 0) {
    Interpreter.raiseArgumentError(
      `membership list for attribute ${inspectName(name)} must not be empty`,
    );
  }

  operand.data.forEach((value) => {
    if (Type.isList(value) || Type.isTuple(value) || isStruct(value, "Range")) {
      Interpreter.raiseArgumentError(
        `invalid membership list element ${Interpreter.inspect(value)} for attribute ${inspectName(name)} - membership lists hold plain values`,
      );
    }
  });
}

function validateMembershipRange(range, name, entityType) {
  const type = nameType(entityType, name);

  if (type !== "integer") {
    Interpreter.raiseArgumentError(
      `range ${Interpreter.inspect(range)} requires an integer attribute - attribute ${inspectName(name)} in ${entityType} has type :${type}`,
    );
  }

  if (field(range, "step").value !== 1n) {
    Interpreter.raiseArgumentError(
      `stepped range ${Interpreter.inspect(range)} for attribute ${inspectName(name)} is not supported - membership ranges use step 1`,
    );
  }

  if (field(range, "last").value < field(range, "first").value) {
    Interpreter.raiseArgumentError(
      `range ${Interpreter.inspect(range)} for attribute ${inspectName(name)} is empty - it would match nothing`,
    );
  }
}

// A derived field holds no reference, so no relationship goes through it - a related row it holds
// is read through the relationships its definition reads.
function validateNotDerivedHop(hop, entityType, reason) {
  if (Object.hasOwn(Model.derived(entityType), hop.value)) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(hop)} is a derived field in ${entityType} - ${reason}`,
    );
  }
}

// What an attribute operand names - another attribute of the row, or a path to one - refused in the
// words a predicate's own name is, quoted as written, a row above's wrapper included.
function validateOperandName(operandName, entityType) {
  const name = localName(operandName);

  if (Type.isAtom(name)) {
    validateFilteredName(name, entityType);

    return;
  }

  if (!isPath(name)) {
    Interpreter.raiseArgumentError(
      `invalid attribute operand ${Interpreter.inspect(Type.tuple([Type.atom("attribute"), operandName]))} - an attribute is named by an atom, and a path by a list of two or more atoms`,
    );
  }

  validatePath(name, entityType);
}

// The types an ordering line can be drawn through: every type but boolean and uuid has an order
// to compare by. An enum's is the list it declares, on every tier. A string's is the same derived
// key its ordering uses, which the kernel reads off the row.
function validateOrderableAttribute(name, entityType, operator) {
  if (isDerivedString(entityType, name)) {
    Interpreter.raiseArgumentError(
      `operator :${operator} requires an orderable attribute - ${inspectName(name)} in ${entityType} is a derived string, and a string compares by the sort key stored with it, which a computed string has none of`,
    );
  }

  const type = nameType(entityType, name);

  if (!ORDERABLE_TYPES.includes(type)) {
    Interpreter.raiseArgumentError(
      `operator :${operator} requires an orderable attribute - attribute ${inspectName(name)} in ${entityType} has type :${type}, and boolean and uuid attributes have no order to compare by`,
    );
  }
}

// A path is followed hop by hop from the queried type, each hop a to-one relationship of the type
// the hops before it lead to, and its last name is filterable on the type it ends at - so every
// refusal names the type it was asked of, as on the server.
function validatePath(path, entityType) {
  const names = path.data;

  const endType = names
    .slice(0, -1)
    .reduce((type, hop) => validatePathHop(hop, type), entityType);

  validateFilteredName(names[names.length - 1], endType);
}

function validatePathHop(hop, entityType) {
  if (Object.hasOwn(Model.inverses(entityType), hop.value)) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(hop)} is an inverse relationship in ${entityType} - a path in a condition goes through to-one relationships that hold their reference`,
    );
  }

  const relationship = Model.entry(entityType).relationships[hop.value];

  if (relationship && relationship.toMany) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(hop)} is a to-many relationship in ${entityType} - a path in a condition goes through to-one relationships only`,
    );
  }

  if (relationship) {
    return relationship.type;
  }

  if (attributeNames(entityType).includes(hop.value)) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(hop)} is an attribute in ${entityType} - a path goes through relationships, and only its last name is an attribute`,
    );
  }

  validateNotDerivedHop(
    hop,
    entityType,
    "a path in a condition goes through to-one relationships that hold their reference",
  );

  const known = relationshipNames(entityType)
    .map((relationshipName) => `:${relationshipName}`)
    .join(", ");

  Interpreter.raiseArgumentError(
    `unknown relationship ${Interpreter.inspect(hop)} in ${entityType} - known relationships: ${known}`,
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
      `invalid operand ${Interpreter.inspect(operand)} for operator :${operator} on attribute ${inspectName(name)}`,
    );
  }
}

// A search matches text, so it reads a string attribute - its value, or its folded form for a
// loose match.
function validateSearchableAttribute(name, entityType, operator) {
  if (isDerivedString(entityType, name)) {
    Interpreter.raiseArgumentError(
      `operator :${operator} requires a stored string - ${inspectName(name)} in ${entityType} is a derived string, and a search reads the forms stored with a string`,
    );
  }

  const type = nameType(entityType, name);

  if (type !== "string") {
    Interpreter.raiseArgumentError(
      `operator :${operator} requires a string attribute - attribute ${inspectName(name)} in ${entityType} has type :${type}`,
    );
  }
}

// A source follows any relationships and ends at a set - a to-many, an inverse set or a derived
// set - whose type its predicates are about.
function validateSource(hops, entityType) {
  const ownerType = hops
    .slice(0, -1)
    .reduce((type, hop) => validateSourceHop(hop, type), entityType);

  return validateSourceSet(hops[hops.length - 1], ownerType);
}

// A source follows any relationship to its set - a to-one, a to-many or an inverse of either kind.
// A set before the last link reads as the rows every path reaches.
function validateSourceHop(hop, entityType) {
  const inverses = Model.inverses(entityType);
  const relationships = Model.relationships(entityType);

  if (Object.hasOwn(inverses, hop.value)) {
    return inverses[hop.value].type;
  }

  if (Object.hasOwn(relationships, hop.value)) {
    return relationships[hop.value].type;
  }

  validateNotDerivedHop(
    hop,
    entityType,
    "a quantifier's source goes through relationships, with a derived set only at its end",
  );

  raiseUnknownSourceName(hop, entityType);
}

function validateSourceSet(name, entityType) {
  const inverses = Model.inverses(entityType);

  if (Object.hasOwn(inverses, name.value)) {
    if (inverses[name.value].toMany) {
      return inverses[name.value].type;
    }

    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(name)} is an inverse relationship holding one row in ${entityType} - any, none and all ask about the rows of a to-many relationship`,
    );
  }

  const relationship = Model.relationships(entityType)[name.value];

  if (relationship && relationship.toMany) {
    return relationship.type;
  }

  if (relationship) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(name)} is a to-one relationship in ${entityType} - any, none and all ask about the rows of a to-many relationship - compare the related row through a path: ${name.value}.<attribute>`,
    );
  }

  const derivedTarget = derivedSetTarget(
    name,
    entityType,
    "any, none and all ask about the rows of a set",
  );

  if (derivedTarget) {
    return derivedTarget;
  }

  raiseUnknownSourceName(name, entityType);
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

  if (named !== null && Object.hasOwn(Model.derived(entityType), named)) {
    Interpreter.raiseArgumentError(
      Model.derivedReadOnlyMessage(entityType, named),
    );
  }

  const known = counters.map((counter) => `:${counter}`).join(", ");

  Interpreter.raiseArgumentError(
    `unknown attribute ${spelled} in ${entityType} - known counters: ${known}`,
  );
}

function validateEdgeRelationshipName(name, entityType, stage) {
  const toManyNames = toManyRelationshipNames(entityType);
  const named = Type.isAtom(name) ? name.value : null;

  if (named !== null && toManyNames.includes(named)) {
    return;
  }

  const spelled = Interpreter.inspect(name);

  if (named !== null && Object.hasOwn(Model.inverses(entityType), named)) {
    Interpreter.raiseArgumentError(
      `${spelled} is an inverse relationship in ${entityType} - it reads ${Model.describeInverse(entityType, named)}, so ${inverseWriteFix(entityType, named, stage)}`,
    );
  }

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

  if (named !== null && Object.hasOwn(Model.derived(entityType), named)) {
    Interpreter.raiseArgumentError(
      Model.derivedReadOnlyMessage(entityType, named),
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

  if (named !== null && Object.hasOwn(Model.inverses(entityType), named)) {
    Interpreter.raiseArgumentError(
      `${spelled} is an inverse relationship in ${entityType} - only attributes can be put - it reads ${Model.describeInverse(entityType, named)}, so write that instead`,
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

  if (named !== null && Object.hasOwn(Model.derived(entityType), named)) {
    Interpreter.raiseArgumentError(
      Model.derivedReadOnlyMessage(entityType, named),
    );
  }

  const known = settable.map((settableName) => `:${settableName}`).join(", ");

  Interpreter.raiseArgumentError(
    `unknown attribute ${spelled} in ${entityType} - known attributes: ${known}`,
  );
}

// A set, stored or inverse, is read in the order its declaration names when the include sets none,
// as the server normalizes it. The build bakes that order already spelled the way a term spells
// one, on every to-many and every inverse.
function withDeclaredOrder(subTerm, entityType, name) {
  if (subTerm.sort.length > 0) {
    return subTerm;
  }

  const declared = declaredOrder(entityType, name);

  return declared.length > 0 ? {...subTerm, sort: declared} : subTerm;
}

// Every set-returning shape gets a total order, since two rows the ordering does not tell apart
// would otherwise come back in whatever order the rows happen to sit in. A count is order-blind,
// and a to-one embeds a single entity, so neither takes one.
const Elixir_Hologram_Query_Stage = {
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

    // The entity refusal wins, then the operation's, then the double-claim's - the server's order.
    Model.validateOperation(entityTypeOf(entity, "authorize"), operation);

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

    if (!isPredicateList(predicates)) {
      Interpreter.raiseArgumentError(
        `filter predicates must be a list of name and value pairs - a name being an attribute or a path - got: ${Interpreter.inspect(predicates)}`,
      );
    }

    const clauses = predicates.data.flatMap((pair) =>
      entryClauses(pair, [term.entity]),
    );

    return {...term, filter: [...term.filter, ...clauses]};
  },
  "include/2": (query, spec) => {
    if (Type.isAtom(spec)) {
      return includeOne(query, spec, null);
    }

    if (Type.isList(spec)) {
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

  // The canonical form of a query - what the kernel runs literally.
  "normalize/1": (query) => normalizedTerm(toTerm(query)),

  "one/1": (query) => setCardinality(query, "one"),

  "put_attribute/2": (entity, values) => {
    const entityType = entityTypeOf(entity, "put_attribute");
    const pairs = putPairs(values, "put_attribute");

    for (const [name] of pairs) {
      validatePutName(name, entityType);
    }

    return putAttributes(entity, pairs);
  },

  "put_attribute/3": (entity, name, value) =>
    Elixir_Hologram_Query_Stage["put_attribute/2"](
      entity,
      Type.list([Type.tuple([name, value])]),
    ),

  "skip/2": (query, value) => setViewBound(query, "skip", value),

  "sort/2": (query, spec) => {
    const term = toTerm(query);

    return {...term, sort: orderEntries(spec, term.entity)};
  },

  "take/2": (query, value) => setViewBound(query, "take", value),

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

export default Elixir_Hologram_Query_Stage;
