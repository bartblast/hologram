"use strict";

import Bitstring from "../../bitstring.mjs";
import Elixir_Hologram_Query from "./query.mjs";
import Interpreter from "../../interpreter.mjs";
import LocalDatabase from "../../local_database.mjs";
import Model from "../../model.mjs";
import QueryKernel from "../../query_kernel.mjs";
import Type from "../../type.mjs";

// The data verbs, hand-written for the client the way the query stages are.
//
// One spelling on both tiers is the point: a domain helper reading and writing through these
// moves between an action, a command and a job untouched. What differs underneath is only where
// the rows are - the server reaches Postgres, and this reaches the client's own database through
// the overlay, so a read sees the writes the action made on the line before.
//
// No policy branch, where the server has one. The server filters a read by the acting user's
// policies because its database holds every row; this database holds only rows the server already
// decided this client may see, so filtering again would be asking the same question twice with
// less information. The acting user is still carried, for the predicates that NAME them.
const ID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

// Placeholders exist only in compiler-registered queries, which the renderer runs with values
// bound. One reaching a directly executed read has no value and never will.
function assertNoPlaceholders(term) {
  const [name] = placeholderNames(term);

  if (name !== undefined) {
    Interpreter.raiseArgumentError(
      `cannot read a query term containing placeholders - placeholder :${name} has no value: directly executed queries embed concrete runtime values, placeholders exist only in compiler-registered queries`,
    );
  }
}

function placeholderNames(term) {
  const fromFilter = term.filter.flatMap(([name, _operator, value]) => [
    ...valuePlaceholderNames(name),
    ...valuePlaceholderNames(value),
  ]);

  const fromBounds = [term.limit, term.offset].flatMap(valuePlaceholderNames);

  const fromOrder = term.orderBy.flatMap(([key, direction]) => [
    ...valuePlaceholderNames(key),
    ...valuePlaceholderNames(direction),
  ]);

  const fromIncludes = Object.values(term.include).flatMap(placeholderNames);

  return [...fromFilter, ...fromBounds, ...fromOrder, ...fromIncludes];
}

function validateEntityType(query) {
  if (!Type.isAlias(query) || !Model.isEntityType(structName(query))) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(query)} is not an entity type module - a by-id read takes the entity type, a query term is read with read/1`,
    );
  }
}

function validateId(id) {
  if (!Type.isBitstring(id) || !ID_PATTERN.test(Bitstring.toText(id))) {
    Interpreter.raiseArgumentError(
      `invalid id ${Interpreter.inspect(id)} - entity ids are canonical lowercase 8-4-4-4-12 UUID strings`,
    );
  }
}

function structName(value) {
  return value.value.replace(/^Elixir\./, "");
}

function valuePlaceholderNames(value) {
  if (Array.isArray(value)) {
    return value.flatMap(valuePlaceholderNames);
  }

  return value !== null && typeof value === "object" && "placeholder" in value
    ? [value.placeholder]
    : [];
}

const Elixir_Hologram_DB = {
  "read/1": (query) => {
    const term = Elixir_Hologram_Query["normalize/1"](query);

    assertNoPlaceholders(term);

    const result = QueryKernel.run(term, {
      actorUserId: LocalDatabase.actorUserId,
    });

    return Model.boxResult(term, result);
  },

  "read/2": (entityType, id) => {
    validateId(id);
    validateEntityType(entityType);

    const query = Elixir_Hologram_Query["one/1"](
      Elixir_Hologram_Query["filter/2"](
        entityType,
        Type.list([Type.tuple([Type.atom("id"), id])]),
      ),
    );

    return Elixir_Hologram_DB["read/1"](query);
  },
};

export default Elixir_Hologram_DB;
