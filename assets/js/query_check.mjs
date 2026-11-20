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
// WARNING: must match Hologram.Component.Derived.QueryCheck.server_only_refusal/1, messages
// included.
export default class QueryCheck {
  // Why the given normalized query term can't be a derived field's query, as the rest of a sentence
  // about it, or null when it can.
  static refusal(term) {
    return QueryCheck.#serverOnlyRefusal(term);
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
      (current, name) => QueryCheck.#relatedType(current, name),
      type,
    );
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
    ].filter(({name, type}) => Model.entry(type).serverOnly.has(name));

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
