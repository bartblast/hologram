"use strict";

import Interpreter from "../../interpreter.mjs";
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

const Elixir_Hologram_Query = {
  "count/1": (query) => setCardinality(query, "count"),
  "limit/2": (query, value) => setViewBound(query, "limit", value),
  "offset/2": (query, value) => setViewBound(query, "offset", value),
  "one/1": (query) => setCardinality(query, "one"),
};

export default Elixir_Hologram_Query;
