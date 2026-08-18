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

// A stage takes either the module a query starts from or the term a previous stage returned. A
// term is a plain object here, so it is told from a boxed module by being one.
//
// Membership in the model is what stands for the entity check: the model carries every type
// this client can hold, so a name missing from it is either not an entity type or one whose
// rows never reach a client - neither is a query this side can answer.
function toTerm(query) {
  if (query !== null && typeof query === "object" && "entity" in query) {
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
  "limit/2": (query, value) => setViewBound(query, "limit", value),
  "offset/2": (query, value) => setViewBound(query, "offset", value),
  "one/1": (query) => setCardinality(query, "one"),

  "order_by/2": (query, spec) => {
    const term = toTerm(query);

    return {
      ...term,
      orderBy: [...term.orderBy, ...orderEntries(spec, term.entity)],
    };
  },
};

export default Elixir_Hologram_Query;
