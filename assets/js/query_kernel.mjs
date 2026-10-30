"use strict";

import HologramRuntimeError from "./errors/runtime_error.mjs";
import LocalDatabase from "./local_database.mjs";
import Model from "./model.mjs";
import SortKey from "./sort_key.mjs";

// The kernel the client answers its own queries with: the locked operator set evaluated over
// the rows as the wire spells them - plain values, dates and datetimes and times and enums and
// uuids as strings.
//
// A filter is a list of clauses that all hold. A clause is a triple array - [name, operator,
// operand] - or a disjunction, {or: alternatives}, holding when one of its alternatives does, each
// alternative a clause list of its own. An operand is a value, the acting user ({actor: true}), a
// placeholder ({placeholder: name}) or another attribute of the same row ({attribute: name}). A
// name - in a triple or an attribute operand - is an attribute, or a path: an array of the to-one
// relationships followed from the row and the attribute of the row they lead to, read out of the
// related type's table and missing when a reference is empty or names a row not held.
//
// Hologram.Query.Interpreter is the reference it is pinned to, case for case, and that one is
// pinned to the database executor in turn. What is written twice is this small frozen surface,
// and neither writing is trusted on its own.
//
// Temporal values compare as the strings they are: every datetime on the wire is UTC and every
// datetime and time is at one fractional precision, so the order of the characters IS the order
// of the instants - which is what lets a comparison here be a comparison rather than a parse.
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
    const ranks = QueryKernel.#ranksFor(term.entity, term.filter);

    const matched = Object.values(LocalDatabase.getTable(term.entity)).filter(
      (row) =>
        QueryKernel.#matches(row, term.filter, context, ranks, term.entity),
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

  // The entity type is what an enum predicate is answered by: its declared value list decides
  // which of two labels comes first, and a caller that names its type gets the same answer run()
  // gives. Left out, nothing is ranked and labels compare as they are spelled - and a path cannot
  // be followed at all, since what its relationships lead to is a fact about the type.
  static matches(row, filter, context = {}, entityType = null) {
    if (
      (entityType === null || entityType === undefined) &&
      QueryKernel.#namesPath(filter)
    ) {
      throw new HologramRuntimeError(
        "a filter with a path needs the entity type of the rows it matches",
      );
    }

    const ranks = QueryKernel.#ranksFor(entityType, filter);

    return QueryKernel.#matches(row, filter, context, ranks, entityType);
  }

  // Every predicate triple of the filter, in order, the ones inside a disjunction's alternatives
  // included - Hologram.Query.Stage.triples/1 is its twin.
  static triples(filter) {
    return filter.flatMap((clause) =>
      Array.isArray(clause) ? [clause] : clause.or.flatMap(QueryKernel.triples),
    );
  }

  static #arrange(rows, term) {
    return QueryKernel.#bound(
      QueryKernel.#sort(rows, term.sort, term.entity),
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

  static #compareRows(left, right, keys, ranks) {
    for (const [name, direction] of keys) {
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

  // The row a name is read off and the attribute read there: the row itself for an attribute, and
  // for a path the row its relationships lead to - none when a reference is empty or names a row
  // the database does not hold, since a fill arrives in pieces.
  static #endOf(row, name, entityType) {
    if (!Array.isArray(name)) {
      return {name, row};
    }

    let current = row;
    let currentType = entityType;

    for (const relationshipName of name.slice(0, -1)) {
      const targetId = current[`${relationshipName}_id`] ?? null;
      const targetType =
        Model.relationships(currentType)[relationshipName].type;

      current =
        targetId === null ? null : LocalDatabase.getRow(targetType, targetId);

      if (current === null) {
        return {name: name[name.length - 1], row: null};
      }

      currentType = targetType;
    }

    return {name: name[name.length - 1], row: current};
  }

  // What an enum compares by: each declared value against its position in the list the type
  // declares, built once per run and only for the names that need it - the ordering keys and the
  // filtered attributes alike. A name of any other type is absent, and its comparison is the
  // ordinary one.
  static #enumRanks(entityType, names) {
    const entry = Model.entry(entityType);
    const ranks = {};

    for (const name of names) {
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
    const ranks = QueryKernel.#ranksFor(subTerm.entity, subTerm.filter);

    const targets = Array.from(
      LocalDatabase.getTargetIds(entityType, name, row.id),
    )
      .map((targetId) => table[targetId] ?? null)
      .filter(
        (target) =>
          target !== null &&
          QueryKernel.#matches(
            target,
            subTerm.filter,
            context,
            ranks,
            subTerm.entity,
          ),
      );

    return QueryKernel.#arrange(targets, subTerm).map((target) =>
      QueryKernel.#node(target, subTerm, context),
    );
  }

  // A label beginning with an uppercase letter names a module, which Elixir inspects without a
  // leading colon - the same rule the model reads row values by, so a refusal here is spelled
  // the way the reference spells it.
  static #inspectEnumValue(label) {
    return label[0] >= "A" && label[0] <= "Z" ? label : `:${label}`;
  }

  static #isAttribute(operand) {
    return (
      operand !== null &&
      typeof operand === "object" &&
      !Array.isArray(operand) &&
      "attribute" in operand
    );
  }

  // A visitor has no acting user, and each triple naming one answers false on its own - so a
  // disjunction needs no case for it: the alternative asking about nobody fails, and the others
  // still answer.
  static #matches(row, filter, context, ranks, entityType) {
    return filter.every((clause) =>
      Array.isArray(clause)
        ? QueryKernel.#matchesTriple(row, clause, context, ranks, entityType)
        : clause.or.some((alternative) =>
            QueryKernel.#matches(row, alternative, context, ranks, entityType),
          ),
    );
  }

  // Another attribute of the same row, or one a path reaches, is read the way the predicate's own
  // side is, and compared by the predicate's attribute's ranks - two enums compare only when they
  // declare the same list, so one serves both.
  static #matchesTriple(
    row,
    [name, operator, operand],
    context,
    ranks,
    entityType,
  ) {
    const ranksForKey = ranks[QueryKernel.#nameKey(name)];

    const value = QueryKernel.#isAttribute(operand)
      ? QueryKernel.#read(row, operand.attribute, entityType)
      : QueryKernel.#resolve(operand, context, ranksForKey);

    const end = QueryKernel.#endOf(row, name, entityType);
    const sortName = `${end.name}_sort`;

    // A row filed by ingest carries the key beside every string attribute, so the presence of
    // the field is what says "this is a string" - no model lookup.
    const pair =
      end.row !== null && sortName in end.row
        ? [end.row[sortName], end.row[end.name] ?? null]
        : null;

    return value === QueryKernel.#NO_ACTOR
      ? false
      : QueryKernel.#satisfies(
          operator,
          end.row === null ? null : (end.row[end.name] ?? null),
          value,
          ranksForKey,
          pair,
        );
  }

  // Whether a filter reads a path anywhere - on either side of a comparison, in any alternative -
  // which only a caller naming the rows' type can follow.
  static #namesPath(filter) {
    return QueryKernel.triples(filter).some(
      ([name, _operator, operand]) =>
        Array.isArray(name) ||
        (QueryKernel.#isAttribute(operand) && Array.isArray(operand.attribute)),
    );
  }

  // The key a name's ranks are kept under - a path's names joined, which no attribute name can
  // spell.
  static #nameKey(name) {
    return Array.isArray(name) ? name.join(".") : name;
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

  // The ranks a filter's own predicates compare by, keyed by the name each predicate is written
  // with - an attribute or a path, whose ranks are those of the attribute it ends at - the ones
  // inside a disjunction's alternatives included. A caller that names no type ranks nothing, which
  // is what the raw comparison already was.
  static #ranksFor(entityType, filter) {
    if (entityType === null || entityType === undefined) {
      return {};
    }

    const ranks = {};

    for (const [name] of QueryKernel.triples(filter)) {
      const declaringType = Array.isArray(name)
        ? Model.pathTarget(entityType, name.slice(0, -1))
        : entityType;

      const declaredName = Array.isArray(name) ? name[name.length - 1] : name;

      const declared = QueryKernel.#enumRanks(declaringType, [declaredName]);

      if (declared[declaredName]) {
        ranks[QueryKernel.#nameKey(name)] = declared[declaredName];
      }
    }

    return ranks;
  }

  static #read(row, name, entityType) {
    const end = QueryKernel.#endOf(row, name, entityType);

    return end.row === null ? null : (end.row[end.name] ?? null);
  }

  static #resolve(operand, context, ranksForKey) {
    if (Array.isArray(operand)) {
      return operand.map((element) =>
        QueryKernel.#resolve(element, context, ranksForKey),
      );
    }

    if (operand === null || typeof operand !== "object") {
      return operand;
    }

    if (operand.actor) {
      return context.actorUserId ?? QueryKernel.#NO_ACTOR;
    }

    const value = QueryKernel.#resolvePlaceholder(operand.placeholder, context);

    return QueryKernel.#validateDeclaredValue(
      value,
      operand.placeholder,
      ranksForKey,
    );
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
  static #sort(rows, keys, entityType) {
    const names = keys.map(([name]) => name);
    const ranks = QueryKernel.#enumRanks(entityType, names);

    return [...rows].sort((left, right) =>
      QueryKernel.#compareRows(left, right, keys, ranks),
    );
  }

  // Null is a value like any other to the equality family - an unset attribute is unequal to a
  // set one, and a list may name it - while an ordering line has no place to put one, so a
  // comparison passes over what is not there.
  static #satisfies(operator, value, operand, ranksForKey, pair = null) {
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

    // Only an attribute operand can be missing here - a literal null ordering operand is refused
    // when the query is built, and a placeholder never binds one.
    if (value === null || operand === null) {
      return false;
    }

    const result = QueryKernel.#compareOrderingValues(
      value,
      operand,
      ranksForKey,
      pair,
    );

    switch (operator) {
      case "<":
        return result < 0;

      case "<=":
        return result <= 0;

      case ">":
        return result > 0;

      case ">=":
        return result >= 0;
    }
  }

  // An enum compares by the pair of positions its declared list gives the two labels, and a string
  // by the pair its ordering sorts by - the key carries the order, and the value behind it settles
  // what the key cannot, since the key is a bounded prefix of it. Either way what sorts after a
  // value compares greater than it, which is what makes a bound a position in the list.
  static #compareOrderingValues(value, operand, ranksForKey, pair) {
    if (ranksForKey) {
      return QueryKernel.#compare(
        ranksForKey.get(value),
        ranksForKey.get(operand),
      );
    }

    if (pair === null) {
      return QueryKernel.#compare(value, operand);
    }

    const keyResult = QueryKernel.#compare(pair[0], SortKey.compute(operand));

    return keyResult === 0 ? QueryKernel.#compare(pair[1], operand) : keyResult;
  }

  // A binding on an enum attribute is one of the values that attribute declares, refused in the
  // words the reference refuses it in - the Elixir executors validate every binding against the
  // attribute before they evaluate anything. A list bound as a whole is left alone, as it is
  // there.
  static #validateDeclaredValue(value, name, ranksForKey) {
    if (!ranksForKey || Array.isArray(value) || ranksForKey.has(value)) {
      return value;
    }

    const declared = Array.from(ranksForKey.keys())
      .map((label) => QueryKernel.#inspectEnumValue(label))
      .join(", ");

    throw new HologramRuntimeError(
      `invalid value ${QueryKernel.#inspectEnumValue(value)} for placeholder :${name} - expected one of [${declared}]`,
    );
  }
}
