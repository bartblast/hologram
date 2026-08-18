"use strict";

// The kernel the client answers its own queries with: the locked operator set evaluated over
// the rows as the wire spells them - plain values, dates and datetimes and enums and uuids as
// strings.
//
// Hologram.Query.Interpreter is the reference it is pinned to, case for case, and that one is
// pinned to the database executor in turn. What is written twice is this small frozen surface,
// and neither writing is trusted on its own.
//
// Temporal values compare as the strings they are: every datetime on the wire is UTC at one
// fractional precision, so the order of the characters IS the order of the instants - which is
// what lets a comparison here be a comparison rather than a parse.
export default class QueryKernel {
  // Standing for the acting user when there is none. A predicate asking about nobody is
  // answered by nobody, the way an actor-referencing statement is left out of a visitor's.
  static #NO_ACTOR = Symbol("no actor");

  static matches(row, filter, context = {}) {
    return filter.every(([name, operator, operand]) => {
      const value = QueryKernel.#resolve(operand, context);

      return value === QueryKernel.#NO_ACTOR
        ? false
        : QueryKernel.#satisfies(operator, row[name] ?? null, value);
    });
  }

  static #resolve(operand, context) {
    if (Array.isArray(operand)) {
      return operand.map((element) => QueryKernel.#resolve(element, context));
    }

    if (operand === null || typeof operand !== "object") {
      return operand;
    }

    if (operand.actor) {
      return context.actorUserId ?? QueryKernel.#NO_ACTOR;
    }

    return (context.bindings ?? {})[operand.param];
  }

  // Null is a value like any other to the equality family - an unset attribute is unequal to a
  // set one, and a list may name it - while an ordering line has no place to put one, so a
  // comparison passes over what is not there.
  static #satisfies(operator, value, operand) {
    switch (operator) {
      case "!=":
        return value !== operand;

      case "==":
        return value === operand;

      case "in":
        return operand.includes(value);

      case "not_in":
        return !operand.includes(value);
    }

    if (value === null) {
      return false;
    }

    switch (operator) {
      case "<":
        return value < operand;

      case "<=":
        return value <= operand;

      case ">":
        return value > operand;

      case ">=":
        return value >= operand;
    }
  }
}
