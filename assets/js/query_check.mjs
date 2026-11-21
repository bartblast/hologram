"use strict";

import Model from "./model.mjs";

// Based on Hologram.Component.Derived.QueryCheck
//
// What a derived field's query must not ask for in the browser: an attribute the browser never
// holds. A claim of trust needs no check here - the client's trust/1 already refuses one, since the
// browser has no server authority to claim. Nor does a type no rule lets anyone read, which the
// server refuses on its render: a deploy changing only the rules hands an open tab rules leaving
// such a type none, and that tab answers its query from the rows it holds rather than failing its
// render.
//
// Names are resolved the way Hologram.Query.Stage's predicate_references/1 resolves them: from the
// queried row, through each quantifier's source, an outer name reading the row that many quantifiers
// out.
//
// It also tells whether the browser can answer a query at all: one reading a type sync never sends
// - one no browser code names - answers from rows that are never kept current.
//
// WARNING: must match Hologram.Component.Derived.QueryCheck.server_only_refusal/1 and, for
// unsyncedRefusal, validate_synced_types!/3 in Hologram.Template.Renderer, messages included.
export default class QueryCheck {
  // Why the given normalized query term can't be a derived field's query, as the rest of a sentence
  // about it, or null when it can.
  static refusal(term) {
    return QueryCheck.#serverOnlyRefusal(term);
  }

  // Why the browser can't answer the given normalized query term, as the rest of a sentence about
  // it, or null when it can: the term reads a type the bundle lists among the ones sync sends no
  // rows of (Hologram.sync.syncedTypes). A bundle without the list, like one built before it,
  // checks nothing. A type the bundle's model doesn't hold, which a name built at run time can
  // reach, is told as unsynced rather than walked.
  static unsyncedRefusal(term) {
    const synced = globalThis.Hologram.sync?.syncedTypes;

    if (!Array.isArray(synced)) {
      return null;
    }

    const syncedSet = new Set(synced);

    const readTypes = Model.isEntityType(term.entity)
      ? QueryCheck.#readTypes(term, new Set())
      : [term.entity];

    const unsynced = [...new Set(readTypes)]
      .filter((type) => !syncedSet.has(type))
      .sort();

    if (unsynced.length === 0) {
      return null;
    }

    const rows = unsynced.length === 1 ? "its rows" : "their rows";

    return `reads ${unsynced.join(", ")}, which browser code never names, so sync never sends ${rows} - name the entity type, or the relationship or derived field leading to it, as written in browser code, like include(project) or %Project{}`;
  }

  // Based on the chains Hologram.Query.Stage's relationship_chains/1 lists: the relationships each
  // path and each quantifier's source follows from the queried row.
  static #chains(clauses, prefixes) {
    return clauses.flatMap((clause) => {
      if (Array.isArray(clause)) {
        const [name, _operator, operand] = clause;

        return [name, QueryCheck.#operandName(operand)]
          .filter((each) => each !== null)
          .map((each) => QueryCheck.#resolvedName(each, prefixes))
          .filter((path) => Array.isArray(path) && path.length >= 2)
          .map((path) => path.slice(0, -1));
      }

      if (Object.hasOwn(clause, "or")) {
        return clause.or.flatMap((alternative) =>
          QueryCheck.#chains(alternative, prefixes),
        );
      }

      const chain = QueryCheck.#sourceChain(clause.source, prefixes);

      return [
        chain,
        ...QueryCheck.#chains(clause.filter, [chain, ...prefixes]),
      ];
    });
  }

  // The types a derived field's definition reads, from the row of the given type it is computed for:
  // its queries' types and the rows along their sources, and what the names, conditions and
  // branches it is built from read on that row.
  static #definitionTypes(definition, ownerType, seen) {
    // A definition's query is about the rows its source leads to from the row it is computed for,
    // and names that row one quantifier out, as Hologram.Query.Window reads it. Every definition's
    // query has a source (Hologram.Entity.Derived.lower/1).
    if ("query" in definition) {
      const term = definition.query;
      const {chain, owner} = term.source;

      return [
        ...QueryCheck.#hopTypes(owner, chain, seen),
        ...QueryCheck.#readTypesFrom(term, owner, [chain, []], seen),
      ];
    }

    if ("if" in definition) {
      return [
        ...QueryCheck.#rowClauseTypes(definition.if, ownerType, seen),
        ...QueryCheck.#definitionTypes(definition.then, ownerType, seen),
        ...QueryCheck.#definitionTypes(definition.else, ownerType, seen),
      ];
    }

    if ("concat" in definition) {
      return definition.concat.flatMap((operand) =>
        QueryCheck.#definitionTypes(operand, ownerType, seen),
      );
    }

    if ("condition" in definition) {
      return QueryCheck.#rowClauseTypes(definition.condition, ownerType, seen);
    }

    if ("name" in definition) {
      const path = Array.isArray(definition.name)
        ? definition.name
        : [definition.name];

      const hops = path.slice(0, -1);
      const target = QueryCheck.#pathTarget(ownerType, hops);

      return [
        ...QueryCheck.#hopTypes(ownerType, hops, seen),
        ...QueryCheck.#derivedTypes(target, path[path.length - 1], seen),
      ];
    }

    return [];
  }

  // What reading the named derived field of the given type reads: the rows it holds and what its
  // definition reads. Each field is walked once, so fields reading each other end.
  static #derivedTypes(type, name, seen) {
    const key = `${type}/${name}`;

    if (!Model.isEntityType(type) || seen.has(key)) {
      return [];
    }

    const derived = Model.derivedField(type, name);

    if (derived === null) {
      return [];
    }

    seen.add(key);

    const rowTypes = derived.kind === "scalar" ? [] : [derived.entity];

    const definitionTypes = derived.definition
      ? QueryCheck.#definitionTypes(derived.definition, type, seen)
      : [];

    return [...rowTypes, ...definitionTypes];
  }

  // The types each relationship of the given chain leads to from the given type, and what a derived
  // field among them reads.
  static #hopTypes(type, chain, seen) {
    const types = [];

    // A type the bundle's model doesn't hold leads nowhere it can tell.
    chain.reduce((current, name) => {
      if (current === null || !Model.isEntityType(current)) {
        return null;
      }

      types.push(...QueryCheck.#derivedTypes(current, name, seen));

      const next = QueryCheck.#relatedType(current, name);
      types.push(next);

      return next;
    }, type);

    return types;
  }

  static #joinedName(prefix, name) {
    if (prefix.length === 0) {
      return name;
    }

    return [...prefix, ...(Array.isArray(name) ? name : [name])];
  }

  static #operandName(operand) {
    return operand !== null &&
      typeof operand === "object" &&
      !Array.isArray(operand) &&
      Object.hasOwn(operand, "attribute")
      ? operand.attribute
      : null;
  }

  static #pathTarget(type, relationshipNames) {
    return relationshipNames.reduce(
      (current, name) =>
        current !== null && Model.isEntityType(current)
          ? QueryCheck.#relatedType(current, name)
          : null,
      type,
    );
  }

  // The types the given normalized term reads - its own, the ones its paths and quantifiers' sets go
  // through, the ones the derived fields it reads, sorts on or includes are computed from, and the
  // ones of the terms it includes - as Hologram.Query.Window.entity_types/1 lists them.
  static #readTypes(term, seen) {
    return QueryCheck.#readTypesFrom(term, term.entity, [[]], seen);
  }

  // The same, with the term's names resolved from the given root through the given prefixes, as
  // #references resolves them: the relationships to the term's rows from the root, then to each row
  // above them.
  static #readTypesFrom(term, root, prefixes, seen) {
    const hopTypes = QueryCheck.#chains(term.filter, prefixes).flatMap(
      (chain) => QueryCheck.#hopTypes(root, chain, seen),
    );

    const derivedTypes = [
      ...QueryCheck.#references(term.filter, prefixes).map(({chain, name}) => [
        QueryCheck.#pathTarget(root, chain),
        name,
      ]),
      ...term.sort.map(([name, _direction]) => [term.entity, name]),
      ...Object.keys(term.include).map((name) => [term.entity, name]),
    ].flatMap(([type, name]) => QueryCheck.#derivedTypes(type, name, seen));

    return [
      term.entity,
      ...hopTypes,
      ...derivedTypes,
      ...QueryCheck.#subTerms(term).flatMap((subTerm) =>
        QueryCheck.#readTypes(subTerm, seen),
      ),
    ];
  }

  // The names the clauses read, each as the relationships from the queried row to the row it is an
  // attribute of, and its own name.
  static #references(clauses, prefixes) {
    return clauses.flatMap((clause) => {
      if (Array.isArray(clause)) {
        const [name, _operator, operand] = clause;

        return [name, QueryCheck.#operandName(operand)]
          .filter((each) => each !== null)
          .map((each) =>
            QueryCheck.#reference(QueryCheck.#resolvedName(each, prefixes)),
          );
      }

      if (Object.hasOwn(clause, "or")) {
        return clause.or.flatMap((alternative) =>
          QueryCheck.#references(alternative, prefixes),
        );
      }

      const chain = QueryCheck.#sourceChain(clause.source, prefixes);

      return QueryCheck.#references(clause.filter, [chain, ...prefixes]);
    });
  }

  static #reference(name) {
    return Array.isArray(name)
      ? {chain: name.slice(0, -1), name: name[name.length - 1]}
      : {chain: [], name};
  }

  // What clauses read on a row of the given type, like a derived field's condition.
  static #rowClauseTypes(clauses, type, seen) {
    return QueryCheck.#readTypes(
      {entity: type, filter: clauses, include: {}, sort: []},
      seen,
    );
  }

  // The type of the rows a relationship or a derived field holding rows leads to.
  static #relatedType(type, name) {
    const derived = Model.derivedField(type, name);

    return derived ? derived.entity : Model.pathTarget(type, [name]);
  }

  static #resolvedName(name, prefixes) {
    if (name !== null && typeof name === "object" && !Array.isArray(name)) {
      return QueryCheck.#joinedName(prefixes[name.outer], name.name);
    }

    return QueryCheck.#joinedName(prefixes[0], name);
  }

  static #serverOnlyReferences(term) {
    const references = [
      ...QueryCheck.#references(term.filter, [[]]).map(({chain, name}) => ({
        name,
        type: QueryCheck.#pathTarget(term.entity, chain),
      })),
      ...term.sort.map(([name, _direction]) => ({name, type: term.entity})),
    ].filter(
      ({name, type}) => type !== null && Model.entry(type).serverOnly.has(name),
    );

    const namesByType = new Map();

    for (const {name, type} of references) {
      if (!namesByType.has(type)) {
        namesByType.set(type, []);
      }

      namesByType.get(type).push(name);
    }

    const own = namesByType.has(term.entity)
      ? [[term.entity, namesByType.get(term.entity)]]
      : [];

    const paths = [...namesByType.entries()]
      .filter(([type, _names]) => type !== term.entity)
      .sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0));

    return [
      ...[...own, ...paths].map(([type, names]) => [
        type,
        [...new Set(names)].sort(),
      ]),
      ...QueryCheck.#subTerms(term).flatMap((subTerm) =>
        QueryCheck.#serverOnlyReferences(subTerm),
      ),
    ];
  }

  static #serverOnlyRefusal(term) {
    const references = QueryCheck.#serverOnlyReferences(term);

    if (references.length === 0) {
      return null;
    }

    const listing = references
      .map(
        ([type, names]) =>
          `${type} ${names.map((name) => `:${name}`).join(", ")}`,
      )
      .join(", ");

    return `filters or sorts on server_only attributes (${listing}) - the client never holds those values, so it could not evaluate the reference locally. Drop the reference, or read the rows through the trusted backend API.`;
  }

  static #sourceChain(source, prefixes) {
    if (Array.isArray(source)) {
      return [...prefixes[0], ...source];
    }

    return [...prefixes[source.outer], ...source.name];
  }

  // The terms a term includes, in name order. A derived field holding a value is included with
  // nothing under it.
  static #subTerms(term) {
    return Object.keys(term.include)
      .sort()
      .map((name) => term.include[name])
      .filter((subTerm) => subTerm !== null);
  }
}
