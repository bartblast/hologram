"use strict";

import HologramRuntimeError from "./errors/runtime_error.mjs";
import LocalDatabase from "./local_database.mjs";
import Model from "./model.mjs";
import SortKey from "./sort_key.mjs";
import StringOrder from "./string_order.mjs";

// The kernel the client answers its own queries with: the locked operator set evaluated over
// the rows as the wire spells them - plain values, dates and datetimes and times and enums and
// uuids as strings.
//
// A filter is a list of clauses that all hold. A clause is a triple array - [name, operator,
// operand] - a disjunction, {or: alternatives}, holding when one of its alternatives does, each
// alternative a clause list of its own, or a quantifier, {quantifier, source, filter}, holding when
// any, none or all of the rows of a related set match its filter. An operand is a value, the acting
// user ({actor: true}), a placeholder ({placeholder: name}) or another attribute
// ({attribute: name}).
// A name - in a triple or an attribute operand - is an attribute, or a path: an array of the to-one
// relationships followed from the row and the attribute of the row they lead to, read out of the
// related type's table and missing when a reference is empty or names a row not held. Inside a
// quantifier's filter the row is the related one, and {outer: levels, name} names an attribute or a
// path of the row that many quantifiers out. A source is the array of relationships to the set -
// to-one ones, then a to-many, an inverse set or a derived field holding rows - read on the row the
// quantifier is about, or {outer: levels, name} read on a row above.
//
// A derived field holding a value is computed from its definition - the model bakes it - wherever
// its name is read: a predicate's side, a path's end, a sort key. `concat` is null when an operand
// is, an `if` takes its else branch when its condition does not hold, a condition is true or false,
// never null, and a count counts the rows its source leads to from the row - the last link's rows
// of every row the links before it reach, each once - matched to its filter with the row as the row
// above, its bounds applied. A derived field holding rows holds its query's rows in its order with
// its bounds applied, the rows of the branch an `if` takes, or none for null. An included derived
// field holds its value, or its rows - a list, or one row or null - each row embedding what its
// definition and the include ask for. A derived enum compares and orders by its value's position
// among the declared ones. An integer a float field reads needs no widening here, since a number is
// one type whole or not.
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
  static run(term, givenContext = {}) {
    const context = QueryKernel.#withMemo(givenContext);
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
        const [row] = QueryKernel.#arrange(matched, term, context);

        return row ? QueryKernel.#node(row, term, context) : null;
      }

      default:
        return QueryKernel.#arrange(matched, term, context).map((row) =>
          QueryKernel.#node(row, term, context),
        );
    }
  }

  // The entity type is what an enum predicate is answered by: its declared value list decides
  // which of two labels comes first, and a caller that names its type gets the same answer run()
  // gives. Left out, nothing is ranked and labels compare as they are spelled - and a path cannot
  // be followed at all, since what its relationships lead to is a fact about the type. Nor is a
  // derived field computed, since whether a name is one is a fact about the type too: it reads as
  // the row holds it, which is nothing.
  static matches(row, filter, givenContext = {}, entityType = null) {
    const context = QueryKernel.#withMemo(givenContext);

    if (
      (entityType === null || entityType === undefined) &&
      QueryKernel.#needsEntityType(filter)
    ) {
      throw new HologramRuntimeError(
        "a filter with a path or a quantifier needs the entity type of the rows it matches",
      );
    }

    const ranks = QueryKernel.#ranksFor(entityType, filter);

    return QueryKernel.#matches(row, filter, context, ranks, entityType);
  }

  // Every predicate triple of the filter, in order, the ones inside a disjunction's alternatives
  // and a quantifier's filter included, each name as its own level writes it.
  static triples(filter) {
    return filter.flatMap((clause) => {
      if (Array.isArray(clause)) {
        return [clause];
      }

      return "or" in clause
        ? clause.or.flatMap(QueryKernel.triples)
        : QueryKernel.triples(clause.filter);
    });
  }

  static #arrange(rows, term, context) {
    return QueryKernel.#bound(
      QueryKernel.#sort(rows, term.sort, term.entity, context),
      term,
    );
  }

  static #bound(rows, term) {
    const skip = term.skip ?? 0;

    return term.take === null || term.take === undefined
      ? rows.slice(skip)
      : rows.slice(skip, skip + term.take);
  }

  // The rows a source chain leads to from the row: the last link's rows of every row the links
  // before it reach, each row once however many paths reach it.
  static #chainRows(row, entityType, chain, context) {
    let rows = [row];
    let rowsType = entityType;

    for (const name of chain) {
      const seen = new Set();

      rows = rows
        .flatMap((current) =>
          QueryKernel.#linkRows(current, rowsType, name, context),
        )
        .filter((linked) => !seen.has(linked.id) && seen.add(linked.id));

      rowsType = QueryKernel.#relatedType(rowsType, name);
    }

    return rows;
  }

  static #compare(left, right) {
    if (typeof left === "string" && typeof right === "string") {
      return StringOrder.compare(left, right);
    }

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

    const sortName = Model.sortKeyField(name);

    if (sortName in left) {
      const result = QueryKernel.#compare(left[sortName], right[sortName]);

      if (result !== 0) {
        return result;
      }
    }

    return QueryKernel.#compare(left[name], right[name]);
  }

  // The rows a definition of a derived field holding rows holds for the row: a query's rows in its
  // order with its bounds applied, only the first for one row, the rows of the branch an if takes,
  // or none for null.
  static #definitionRows(definition, row, entityType, context) {
    if ("if" in definition) {
      const holds = QueryKernel.#matches(
        row,
        definition.if,
        context,
        QueryKernel.#ranksFor(entityType, definition.if),
        entityType,
      );

      return QueryKernel.#definitionRows(
        holds ? definition.then : definition.else,
        row,
        entityType,
        context,
      );
    }

    if ("query" in definition) {
      const term = definition.query;

      const rows = QueryKernel.#arrange(
        QueryKernel.#sourcedRows(row, entityType, term, context),
        term,
        context,
      );

      return term.cardinality === "one" ? rows.slice(0, 1) : rows;
    }

    return [];
  }

  static #derivedRows(row, entityType, name, context) {
    return QueryKernel.#definitionRows(
      Model.derivedField(entityType, name).definition,
      row,
      entityType,
      context,
    );
  }

  // Computed once per row and name in a run, however many times the run reads it - a filter and a
  // sort over one count, an outer value read for every related row. A row a pending write folds is
  // a fresh object per read, so it is computed again rather than read stale.
  static #derivedValue(row, entityType, name, context) {
    let values = context.derivedMemo.get(row);

    if (values?.has(name)) {
      return values.get(name);
    }

    const value = QueryKernel.#evaluated(
      Model.derivedField(entityType, name).definition,
      row,
      entityType,
      context,
    );

    if (!values) {
      values = new Map();
      context.derivedMemo.set(row, values);
    }

    values.set(name, value);

    return value;
  }

  // The row a name is read off, its type and the field read there: the row itself for an attribute
  // or a derived field, and for a path the row its relationships lead to - none when a reference is
  // empty or names a row the database does not hold, since a fill arrives in pieces. A name of a
  // row above is read on that row, the rows above held nearest first.
  static #endOf(row, name, entityType, outer = []) {
    if (QueryKernel.#isOuter(name)) {
      const above = outer[name.outer - 1];

      return QueryKernel.#endOf(above.row, name.name, above.entityType);
    }

    if (!Array.isArray(name)) {
      return {entityType, name, row};
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
        return {entityType: targetType, name: name[name.length - 1], row: null};
      }

      currentType = targetType;
    }

    return {entityType: currentType, name: name[name.length - 1], row: current};
  }

  // What the end of a name holds: the attribute's value, a derived field's value computed on the
  // row, or null when the row a path leads to is missing.
  static #endValue(end, context) {
    if (end.row === null) {
      return null;
    }

    const derived =
      end.entityType === null || end.entityType === undefined
        ? null
        : Model.derivedField(end.entityType, end.name);

    return derived
      ? QueryKernel.#derivedValue(end.row, end.entityType, end.name, context)
      : (end.row[end.name] ?? null);
  }

  // What an enum compares by: each declared value against its position in the list the type
  // declares, built once per run and only for the names that need it - the ordering keys and the
  // filtered attributes alike. A name of any other type is absent, and its comparison is the
  // ordinary one.
  static #enumRanks(entityType, names) {
    const entry = Model.entry(entityType);
    const ranks = {};

    for (const name of names) {
      const derived = Model.derivedField(entityType, name);

      const values =
        entry.attributes[name] === "enum"
          ? entry.enumValues[name]
          : derived?.kind === "scalar" && derived.type === "enum"
            ? derived.values
            : null;

      if (values) {
        ranks[name] = new Map(values.map((label, index) => [label, index]));
      }
    }

    return ranks;
  }

  // A definition's expression on the row: strings joined, null when one of them is, an if's branch,
  // whether a condition holds, a name of the row, the number of rows a count reads, or a value.
  static #evaluated(definition, row, entityType, context) {
    if ("concat" in definition) {
      const values = definition.concat.map((operand) =>
        QueryKernel.#evaluated(operand, row, entityType, context),
      );

      return values.some((value) => value === null) ? null : values.join("");
    }

    if ("condition" in definition || "if" in definition) {
      const clauses = definition.condition ?? definition.if;

      const holds = QueryKernel.#matches(
        row,
        clauses,
        context,
        QueryKernel.#ranksFor(entityType, clauses),
        entityType,
      );

      if ("condition" in definition) {
        return holds;
      }

      return QueryKernel.#evaluated(
        holds ? definition.then : definition.else,
        row,
        entityType,
        context,
      );
    }

    if ("name" in definition) {
      return QueryKernel.#read(row, definition.name, entityType, [], context);
    }

    if ("query" in definition) {
      return QueryKernel.#bound(
        QueryKernel.#sourcedRows(row, entityType, definition.query, context),
        definition.query,
      ).length;
    }

    return definition.value;
  }

  // The held rows the ids filed for the row name. A pair naming a row the database does not hold is
  // passed over: a fill arrives in pieces, and a parent can be told about a child that has not
  // landed yet.
  static #heldTargets(entityType, name, row, table) {
    return Array.from(LocalDatabase.getTargetIds(entityType, name, row.id))
      .map((targetId) => table[targetId] ?? null)
      .filter((target) => target !== null);
  }

  // A relationship the query asked for is filled from the rest of the database - a to-one by
  // following the id its row carries, a to-many by reading the pairs it is the source of. A derived
  // field is computed from its definition. A row does not say what type it is, and does not need
  // to: the term reading it does.
  static #included(row, entityType, name, subTerm, context) {
    if (Model.derivedField(entityType, name)) {
      return QueryKernel.#includedDerived(
        row,
        entityType,
        name,
        subTerm,
        context,
      );
    }

    const inverses = Model.inverses(entityType);

    if (Object.hasOwn(inverses, name)) {
      return QueryKernel.#includedInverse(
        row,
        entityType,
        name,
        inverses[name],
        subTerm,
        context,
      );
    }

    const {toMany} = Model.relationships(entityType)[name];

    if (!toMany) {
      const table = LocalDatabase.getTable(subTerm.entity);
      const target = table[row[`${name}_id`]] ?? null;

      return target ? QueryKernel.#node(target, subTerm, context) : null;
    }

    return QueryKernel.#includedSet(
      QueryKernel.#relatedRows(row, entityType, name),
      subTerm,
      context,
    );
  }

  // An included derived field holding a value is the value its definition computes for the row. One
  // holding rows holds its definition's rows - a list, or one row or null - each row embedding what
  // the definition and the include ask for.
  static #includedDerived(row, entityType, name, subTerm, context) {
    if (subTerm === null) {
      return QueryKernel.#derivedValue(row, entityType, name, context);
    }

    const rowsTerm = Model.rowsTerm(entityType, name, subTerm);

    const nodes = QueryKernel.#derivedRows(row, entityType, name, context).map(
      (derivedRow) => QueryKernel.#node(derivedRow, rowsTerm, context),
    );

    return Model.derivedField(entityType, name).kind === "set"
      ? nodes
      : (nodes[0] ?? null);
  }

  // An inverse is read from where the relationship it reverses is stored. Of a to-one, it is the
  // related rows whose reference field names the row - read off the table, where a pending move
  // is already folded in. Of a to-many, it is the ids filed for the row itself, the overlay folding
  // in the pending edges of the related rows. A row whose reference is nil names no row, so it
  // belongs to no inverse. A single inverse is the one related row, the first by id while two
  // pending writes disagree about which.
  //
  // The reference kinds scan the related type's table once per parent row - a cost that grows
  // with rows times parents, acceptable at the sizes a client holds.
  static #includedInverse(row, entityType, name, inverse, subTerm, context) {
    const related = QueryKernel.#relatedRows(row, entityType, name);

    if (inverse.toMany) {
      return QueryKernel.#includedSet(related, subTerm, context);
    }

    const [first] = related.sort((left, right) =>
      QueryKernel.#compare(left.id, right.id),
    );

    return first ? QueryKernel.#node(first, subTerm, context) : null;
  }

  // A set of related rows, put through the clauses the include carries - filtered, ordered and
  // bounded like any other.
  static #includedSet(targets, subTerm, context) {
    const ranks = QueryKernel.#ranksFor(subTerm.entity, subTerm.filter);

    const matching = targets.filter((target) =>
      QueryKernel.#matches(
        target,
        subTerm.filter,
        context,
        ranks,
        subTerm.entity,
      ),
    );

    return QueryKernel.#arrange(matching, subTerm, context).map((target) =>
      QueryKernel.#node(target, subTerm, context),
    );
  }

  // A label beginning with an uppercase letter names a module, which Elixir inspects without a
  // leading colon - the same rule the model reads row values by, so a refusal here is spelled
  // the way the reference spells it.
  static #inspectEnumValue(label) {
    return label[0] >= "A" && label[0] <= "Z" ? label : `:${label}`;
  }

  static #isOuter(name) {
    return (
      name !== null &&
      typeof name === "object" &&
      !Array.isArray(name) &&
      "outer" in name
    );
  }

  static #isAttribute(operand) {
    return (
      operand !== null &&
      typeof operand === "object" &&
      !Array.isArray(operand) &&
      "attribute" in operand
    );
  }

  // The rows one link of a source leads to from the row: the related row a to-one names, if the
  // database holds it, or the rows of a set.
  static #linkRows(row, entityType, name, context) {
    const relationship = Object.hasOwn(Model.relationships(entityType), name)
      ? Model.relationships(entityType)[name]
      : null;

    if (relationship && !relationship.toMany) {
      const targetId = row[`${name}_id`] ?? null;
      const target =
        targetId === null
          ? null
          : LocalDatabase.getRow(relationship.type, targetId);

      return target === null ? [] : [target];
    }

    return QueryKernel.#setRows(row, entityType, name, context);
  }

  // A visitor has no acting user, and each triple naming one answers false on its own - so a
  // disjunction needs no case for it: the alternative asking about nobody fails, and the others
  // still answer. The rows above are those a quantifier's filter can name, nearest first.
  static #matches(row, filter, context, ranks, entityType, outer = []) {
    return filter.every((clause) => {
      if (Array.isArray(clause)) {
        return QueryKernel.#matchesTriple(
          row,
          clause,
          context,
          ranks,
          entityType,
          outer,
        );
      }

      if ("or" in clause) {
        return clause.or.some((alternative) =>
          QueryKernel.#matches(
            row,
            alternative,
            context,
            ranks,
            entityType,
            outer,
          ),
        );
      }

      return QueryKernel.#matchesQuantifier(
        row,
        clause,
        context,
        entityType,
        outer,
      );
    });
  }

  // The related rows the source leads to - none when one of its to-one relationships reads no row -
  // matched against the quantifier's filter, with the row it is about as the first row above them.
  static #matchesQuantifier(row, clause, context, entityType, outer) {
    const start = Array.isArray(clause.source)
      ? {entityType, hops: clause.source, row}
      : {...outer[clause.source.outer - 1], hops: clause.source.name};

    let owner = start.row;
    let ownerType = start.entityType;

    for (const hop of start.hops.slice(0, -1)) {
      const targetId = owner[`${hop}_id`] ?? null;
      const targetType = Model.relationships(ownerType)[hop].type;

      owner =
        targetId === null ? null : LocalDatabase.getRow(targetType, targetId);

      // No row to hold the set, so the set has no rows: any fails, none and all hold.
      if (owner === null) {
        return clause.quantifier !== "any";
      }

      ownerType = targetType;
    }

    const setName = start.hops[start.hops.length - 1];
    const related = QueryKernel.#setRows(owner, ownerType, setName, context);
    const relatedType = QueryKernel.#relatedType(ownerType, setName);
    const innerOuter = [{entityType, row}, ...outer];
    const ranks = QueryKernel.#ranksFor(relatedType, clause.filter, innerOuter);

    const holds = (relatedRow) =>
      QueryKernel.#matches(
        relatedRow,
        clause.filter,
        context,
        ranks,
        relatedType,
        innerOuter,
      );

    switch (clause.quantifier) {
      case "all":
        return related.every(holds);

      case "any":
        return related.some(holds);

      case "none":
        return !related.some(holds);
    }
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
    outer,
  ) {
    const ranksForKey = ranks[QueryKernel.#nameKey(name)];

    const value = QueryKernel.#isAttribute(operand)
      ? QueryKernel.#read(row, operand.attribute, entityType, outer, context)
      : QueryKernel.#resolve(operand, context, ranksForKey);

    const end = QueryKernel.#endOf(row, name, entityType, outer);
    const sortName = Model.sortKeyField(end.name);

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
          QueryKernel.#endValue(end, context),
          value,
          ranksForKey,
          pair,
        );
  }

  // The key a name's ranks are kept under - a path's names joined, which no attribute name can
  // spell, and a name of a row above marked with how far out it is.
  static #nameKey(name) {
    if (QueryKernel.#isOuter(name)) {
      return `^${name.outer}:${QueryKernel.#nameKey(name.name)}`;
    }

    return Array.isArray(name) ? name.join(".") : name;
  }

  // Whether a filter reads a path - on either side of a comparison, in any alternative - or holds a
  // quantifier, which only a caller naming the rows' type can follow.
  static #needsEntityType(filter) {
    return filter.some((clause) => {
      if (Array.isArray(clause)) {
        const [name, _operator, operand] = clause;

        return (
          Array.isArray(name) ||
          (QueryKernel.#isAttribute(operand) &&
            Array.isArray(operand.attribute))
        );
      }

      return "or" in clause
        ? clause.or.some((alternative) =>
            QueryKernel.#needsEntityType(alternative),
          )
        : true;
    });
  }

  // The left names of a filter's own predicates, a disjunction's alternatives included - a
  // quantifier's filter is about another row.
  static #levelNames(filter) {
    return filter.flatMap((clause) => {
      if (Array.isArray(clause)) {
        return [clause[0]];
      }

      return "or" in clause ? clause.or.flatMap(QueryKernel.#levelNames) : [];
    });
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
  // with - an attribute or a path, whose ranks are those of the attribute it ends at, on the row
  // the name is read on - the ones inside a disjunction's alternatives included. A quantifier's
  // filter is matched with ranks of its own. A caller that names no type ranks nothing, which is
  // what the raw comparison already was.
  static #ranksFor(entityType, filter, outer = []) {
    if (entityType === null || entityType === undefined) {
      return {};
    }

    const ranks = {};

    for (const name of QueryKernel.#levelNames(filter)) {
      const above = QueryKernel.#isOuter(name) ? outer[name.outer - 1] : null;
      const rowType = above ? above.entityType : entityType;
      const localName = above ? name.name : name;

      const declaringType = Array.isArray(localName)
        ? Model.pathTarget(rowType, localName.slice(0, -1))
        : rowType;

      const declaredName = Array.isArray(localName)
        ? localName[localName.length - 1]
        : localName;

      const declared = QueryKernel.#enumRanks(declaringType, [declaredName]);

      if (declared[declaredName]) {
        ranks[QueryKernel.#nameKey(name)] = declared[declaredName];
      }
    }

    return ranks;
  }

  static #read(row, name, entityType, outer, context) {
    return QueryKernel.#endValue(
      QueryKernel.#endOf(row, name, entityType, outer),
      context,
    );
  }

  // The rows of a set - an inverse of a to-one read off the related table by the reference field,
  // so a pending move is already folded in, an inverse of a to-many and a stored to-many read off
  // the ids filed for the row.
  static #relatedRows(row, entityType, name) {
    const inverses = Model.inverses(entityType);

    if (Object.hasOwn(inverses, name)) {
      const inverse = inverses[name];
      const table = LocalDatabase.getTable(inverse.type);

      if (!inverse.reference) {
        return QueryKernel.#heldTargets(entityType, name, row, table);
      }

      const referenceField = `${inverse.forward}_id`;

      return Object.values(table).filter(
        (candidate) => candidate[referenceField] === row.id,
      );
    }

    const {type} = Model.relationships(entityType)[name];

    return QueryKernel.#heldTargets(
      entityType,
      name,
      row,
      LocalDatabase.getTable(type),
    );
  }

  // The type of the rows a relationship or a derived field holding rows leads to.
  static #relatedType(entityType, name) {
    const derived = Model.derivedField(entityType, name);

    return derived ? derived.entity : Model.pathTarget(entityType, [name]);
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

  // The rows of a set - a relationship's, or the ones a derived field holding them holds.
  static #setRows(row, entityType, name, context) {
    return Model.derivedField(entityType, name)
      ? QueryKernel.#derivedRows(row, entityType, name, context)
      : QueryKernel.#relatedRows(row, entityType, name);
  }

  // Every key of the order is spent before two rows are called equal, and the last of them is
  // always the id, so no two rows ever are. A derived key is computed once per row, onto a view of
  // the row the comparison reads.
  static #sort(rows, keys, entityType, context) {
    const names = keys.map(([name]) => name);
    const ranks = QueryKernel.#enumRanks(entityType, names);

    const derivedNames = names.filter((name) =>
      Model.derivedField(entityType, name),
    );

    const views = rows.map((row) => {
      if (derivedNames.length === 0) {
        return {row, view: row};
      }

      const view = {...row};

      for (const name of derivedNames) {
        view[name] = QueryKernel.#derivedValue(row, entityType, name, context);
      }

      return {row, view};
    });

    return views
      .sort((left, right) =>
        QueryKernel.#compareRows(left.view, right.view, keys, ranks),
      )
      .map(({row}) => row);
  }

  // The rows a derived field's query reads off the owner row, matched to its filter with the owner
  // as the row above them.
  static #sourcedRows(owner, ownerType, term, context) {
    const outer = [{entityType: ownerType, row: owner}];
    const ranks = QueryKernel.#ranksFor(term.entity, term.filter, outer);

    return QueryKernel.#chainRows(
      owner,
      ownerType,
      term.source.chain,
      context,
    ).filter((row) =>
      QueryKernel.#matches(
        row,
        term.filter,
        context,
        ranks,
        term.entity,
        outer,
      ),
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

    // An exact search compares the characters, a loose one the folded forms - case, accents and the
    // letters a sort key spells out folded on both sides.
    switch (operator) {
      case "contains":
        return SortKey.fold(value).includes(SortKey.fold(operand));

      case "contains_exact":
        return value.includes(operand);

      case "starts_with":
        return SortKey.fold(value).startsWith(SortKey.fold(operand));

      case "starts_with_exact":
        return value.startsWith(operand);
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

  // The context a run reads with, holding what it computes of derived fields - one per run, so
  // nothing computed is read by a later one.
  static #withMemo(context) {
    return {...context, derivedMemo: new WeakMap()};
  }
}
