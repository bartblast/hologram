"use strict";

import HologramRuntimeError from "./errors/runtime_error.mjs";
import LocalDatabase from "./local_database.mjs";
import Model from "./model.mjs";

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
//
// What comes back is what the database holds, arranged - never boxed. A result row is a node
// pairing the stored row with what the query included of it, which is the shape the boxing
// boundary reads: entity structs are built from these, once per row, when a result leaves for
// a template.
export default class QueryKernel {
  // Standing for the acting user when there is none. A predicate asking about nobody is
  // answered by nobody, the way an actor-referencing statement is left out of a visitor's.
  static #NO_ACTOR = Symbol("no actor");

  // Runs the term over the database and returns what it evaluates to: nodes for a set, one node
  // or null for a single-result query, a number for a counting one.
  static run(term, context = {}) {
    const matched = Object.values(LocalDatabase.getTable(term.entity)).filter(
      (row) => QueryKernel.matches(row, term.filter, context),
    );

    switch (term.cardinality) {
      // A count counts what the query evaluates to, so the bounds apply before it is taken - and
      // never the order, which cannot change how many there are. A counting query carries no
      // includes either: an embedded entity cannot change how many there are of what holds it.
      case "count":
        return QueryKernel.#bound(matched, term).length;

      case "one": {
        const [row] = QueryKernel.#arrange(matched, term);

        return row ? QueryKernel.#node(row, term, context) : null;
      }

      default:
        return QueryKernel.#arrange(matched, term).map((row) =>
          QueryKernel.#node(row, term, context),
        );
    }
  }

  static matches(row, filter, context = {}) {
    return filter.every(([name, operator, operand]) => {
      const value = QueryKernel.#resolve(operand, context);

      return value === QueryKernel.#NO_ACTOR
        ? false
        : QueryKernel.#satisfies(operator, row[name] ?? null, value);
    });
  }

  static #arrange(rows, term) {
    return QueryKernel.#bound(
      QueryKernel.#sort(rows, term.orderBy, term.entity),
      term,
    );
  }

  static #bound(rows, term) {
    const offset = term.offset ?? 0;

    return term.limit === null || term.limit === undefined
      ? rows.slice(offset)
      : rows.slice(offset, offset + term.limit);
  }

  static #compare(left, right) {
    if (left < right) {
      return -1;
    }

    return left > right ? 1 : 0;
  }

  // Missing values are placed the way the database places them - last when ascending, first when
  // descending - so a page reading its own rows shows them where the server put them.
  static #compareKeys(left, right, name, direction, ranks) {
    const leftValue = left[name] ?? null;
    const rightValue = right[name] ?? null;

    if (leftValue === null || rightValue === null) {
      if (leftValue === rightValue) {
        return 0;
      }

      const nullsLast = direction === "asc" ? 1 : -1;

      return leftValue === null ? nullsLast : -nullsLast;
    }

    const result = QueryKernel.#compareValues(left, right, name, ranks);

    return direction === "desc" ? -result : result;
  }

  static #compareRows(left, right, orderBy, ranks) {
    for (const [name, direction] of orderBy) {
      const result = QueryKernel.#compareKeys(
        left,
        right,
        name,
        direction,
        ranks[name],
      );

      if (result !== 0) {
        return result;
      }
    }

    return 0;
  }

  // A value ordered by a derived key is compared by that key and then by itself, which is the
  // pair of columns the database orders it by - the key carries the practical order, and the
  // value behind it settles what the key cannot, since the key is a bounded prefix of it. An
  // attribute no query orders by carries no key, and is compared as it is.
  //
  // An enum is the one type compared by neither: it orders by its value's position in the
  // declared list, which is the order the database holds the type in, so what compares is the
  // pair of positions rather than the labels.
  static #compareValues(left, right, name, ranks) {
    if (ranks) {
      return QueryKernel.#compare(
        ranks.get(left[name]),
        ranks.get(right[name]),
      );
    }

    const sortName = `${name}_sort`;

    if (sortName in left) {
      const result = QueryKernel.#compare(left[sortName], right[sortName]);

      if (result !== 0) {
        return result;
      }
    }

    return QueryKernel.#compare(left[name], right[name]);
  }

  // What an enum ordering key compares by: each declared value against its position in the list
  // the type declares, built once per sort and only for the keys that need it. A key of any
  // other type is absent, and its comparison is the ordinary one.
  static #enumRanks(entityType, orderBy) {
    const entry = Model.entry(entityType);
    const ranks = {};

    for (const [name] of orderBy) {
      if (entry.attributes[name] === "enum") {
        ranks[name] = new Map(
          entry.enumValues[name].map((label, index) => [label, index]),
        );
      }
    }

    return ranks;
  }

  // A relationship the query asked for is filled from the rest of the database - a to-one by
  // following the id its row carries, a to-many by reading the pairs it is the source of. A row
  // does not say what type it is, and does not need to: the term reading it does.
  static #included(row, entityType, name, subTerm, context) {
    const {toMany} = Model.relationships(entityType)[name];
    const table = LocalDatabase.getTable(subTerm.entity);

    if (!toMany) {
      const target = table[row[`${name}_id`]] ?? null;

      return target ? QueryKernel.#node(target, subTerm, context) : null;
    }

    // A pair naming a row the database does not hold is passed over: a fill arrives in pieces,
    // and a parent can be told about a child that has not landed yet.
    const targets = Array.from(
      LocalDatabase.getTargetIds(entityType, name, row.id),
    )
      .map((targetId) => table[targetId] ?? null)
      .filter(
        (target) =>
          target !== null &&
          QueryKernel.matches(target, subTerm.filter, context),
      );

    return QueryKernel.#arrange(targets, subTerm).map((target) =>
      QueryKernel.#node(target, subTerm, context),
    );
  }

  static #node(row, term, context) {
    const includes = {};

    for (const [name, subTerm] of Object.entries(term.include)) {
      includes[name] = QueryKernel.#included(
        row,
        term.entity,
        name,
        subTerm,
        context,
      );
    }

    return {includes: includes, row: row};
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

    return QueryKernel.#resolvePlaceholder(operand.placeholder, context);
  }

  // Refused in the three cases the reference refuses, and in its words: identity with it covers
  // what each REFUSES, not only what each answers, and this is the executor whose answer reaches
  // a screen. A predicate about the rows that have no value is written as one, in the query,
  // where the operator can be chosen to suit - a LITERAL nil in a term is a value like any other
  // and never comes through here.
  static #resolvePlaceholder(name, context) {
    const bindings = context.bindings ?? {};

    if (!(name in bindings)) {
      throw new HologramRuntimeError(`missing value for placeholder :${name}`);
    }

    const value = bindings[name];

    if (value === null || value === undefined) {
      throw new HologramRuntimeError(
        `nil value for placeholder :${name} - use an explicit nil predicate instead`,
      );
    }

    if (Array.isArray(value) && value.some((element) => element == null)) {
      throw new HologramRuntimeError(
        `nil element in the list for placeholder :${name} - use an explicit nil predicate instead`,
      );
    }

    return value;
  }

  // Every key of the order is spent before two rows are called equal, and the last of them is
  // always the id, so no two rows ever are.
  static #sort(rows, orderBy, entityType) {
    const ranks = QueryKernel.#enumRanks(entityType, orderBy);

    return [...rows].sort((left, right) =>
      QueryKernel.#compareRows(left, right, orderBy, ranks),
    );
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
