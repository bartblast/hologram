"use strict";

import StringOrder from "./string_order.mjs";

// Based on Hologram.Sync.Carry.spell_query/1
//
// A normalized query term spelled as text, the way the server spells its own normalized term of the
// same query, so an answer the page carried is found by the query that gave it. The query holds
// every value it reads, so a changed value is a changed spelling.
//
// A term here is already plain - its values are what the stages unboxed them to, the wire's own
// text for an enum, a date, a datetime and a time - so what's left is to write it out in one order
// both tiers share: an object's members sorted by name, a filter's clauses sorted by their
// spelling all the way down, since the two normalizers sort them by different keys, a boolean as
// text, since an enum may declare true and the server can't tell the two apart by shape, a number
// whole and exact as an integer and any other by its bits.
//
// Every way the two could still differ has to make the spellings differ, never agree: a count whose
// key misses is counted here, one whose key hits wrongly shows a number for another query. So a
// shape this doesn't know is spelled behind a mark the server never writes - and the server marks
// its own unknown shapes with one this never writes.
//
// WARNING: must match spell_query/1 on the server (carry.ex).
export default class QuerySpelling {
  // A term holding any other keys - a source, which only a derived field's query has, or one
  // missing - is a shape the server spells as unknown.
  static spell(term) {
    if (!$.#hasKeys(term, "cardinality,entity,filter,include,skip,sort,take")) {
      return $.#spellUnknown(term);
    }

    return $.#spellObject([
      ["cardinality", $.#spellValue(term.cardinality)],
      ["entity", $.#spellValue(term.entity)],
      ["filter", $.#spellClauses(term.filter)],
      ["include", $.#spellInclude(term.include)],
      ["skip", $.#spellValue(term.skip)],
      ["sort", $.#spellSort(term.sort)],
      ["take", $.#spellValue(term.take)],
    ]);
  }

  // Whether the given value is an object the stages build holding exactly the given keys, sorted and
  // joined by commas - so one holding anything more is a shape this doesn't know.
  static #hasKeys(value, keys) {
    return (
      $.#isPlainObject(value) && Object.keys(value).sort().join(",") === keys
    );
  }

  // An object the stages build, written as a literal in this realm - which a Date, a Map or a value
  // from another realm is not. A boxed term is one too, which only the keys it holds turn away.
  static #isPlainObject(value) {
    return (
      typeof value === "object" &&
      value !== null &&
      Object.getPrototypeOf(value) === Object.prototype
    );
  }

  // The objects a value can be, each the twin of a tuple the server knows: an attribute compared
  // with, a name or a source on a row further out, and a placeholder.
  static #isValueObject(value) {
    return (
      $.#hasKeys(value, "attribute") ||
      $.#hasKeys(value, "name,outer") ||
      $.#hasKeys(value, "placeholder")
    );
  }

  static #sorted(spellings) {
    return spellings.sort(StringOrder.compare);
  }

  static #spellAlternatives(alternatives) {
    const spelled = $.#sorted(alternatives.map($.#spellClauses)).join(",");

    return $.#spellObject([["or", `[${spelled}]`]]);
  }

  static #spellClause(clause) {
    if (Array.isArray(clause) && clause.length === 3) {
      const [name, operator, operand] = clause;

      return `[${$.#spellValue(name)},${$.#spellValue(operator)},${$.#spellValue(operand)}]`;
    }

    if ($.#hasKeys(clause, "or") && Array.isArray(clause.or)) {
      return $.#spellAlternatives(clause.or);
    }

    if ($.#hasKeys(clause, "filter,quantifier,source")) {
      return $.#spellObject([
        ["filter", $.#spellClauses(clause.filter)],
        ["quantifier", $.#spellValue(clause.quantifier)],
        ["source", $.#spellValue(clause.source)],
      ]);
    }

    return $.#spellUnknown(clause);
  }

  // WARNING: must match spell_clauses/1 on the server (carry.ex).
  static #spellClauses(clauses) {
    if (!Array.isArray(clauses)) {
      return $.#spellUnknown(clauses);
    }

    return `[${$.#sorted(clauses.map($.#spellClause)).join(",")}]`;
  }

  static #spellInclude(include) {
    if (!$.#isPlainObject(include)) {
      return $.#spellUnknown(include);
    }

    return $.#spellObject(
      Object.entries(include).map(([name, subTerm]) => [
        name,
        subTerm === null ? "null" : $.spell(subTerm),
      ]),
    );
  }

  // A Number, so 3 and 3.0 are one value here, as they must be on the server. -0 prints as 0.
  //
  // WARNING: must match spell_number/1 on the server (carry.ex).
  static #spellNumber(number) {
    if (
      Number.isInteger(number) &&
      Math.abs(number) <= Number.MAX_SAFE_INTEGER
    ) {
      return String(number);
    }

    const view = new DataView(new ArrayBuffer(8));

    view.setFloat64(0, number);

    const bits = Array.from(new Uint8Array(view.buffer), (byte) =>
      byte.toString(16).padStart(2, "0"),
    ).join("");

    return `float:${bits}`;
  }

  // WARNING: must match spell_object/1 on the server (carry.ex).
  static #spellObject(members) {
    const spelled = members
      .sort(([left], [right]) => StringOrder.compare(left, right))
      .map(([key, spelledValue]) => `${$.#spellString(key)}:${spelledValue}`)
      .join(",");

    return `{${spelled}}`;
  }

  static #spellSort(sort) {
    if (!Array.isArray(sort)) {
      return $.#spellUnknown(sort);
    }

    const spelled = sort
      .map((entry) =>
        Array.isArray(entry) && entry.length === 2
          ? `[${$.#spellValue(entry[0])},${$.#spellValue(entry[1])}]`
          : $.#spellUnknown(entry),
      )
      .join(",");

    return `[${spelled}]`;
  }

  // Only the quote and the backslash are escaped, which is all it takes to tell where a string
  // ends. The key travels in the page's JSON, which escapes everything else.
  //
  // WARNING: must match spell_string/1 on the server (carry.ex).
  static #spellString(text) {
    return `"${text.replace(/[\\"]/g, "\\$&")}"`;
  }

  // Never what the server spells: what it spells starts with a quote, a bracket, a brace, a digit,
  // a minus, `float:`, `null` or the question mark it marks its own unknown shapes with.
  static #spellUnknown(value) {
    let text;

    try {
      text = JSON.stringify(value) ?? String(value);
    } catch {
      text = Object.prototype.toString.call(value);
    }

    return `!${text}`;
  }

  // A name, a path, an operand, a membership list, an attribute compared with, a placeholder and a
  // source, all as the stages left them: plain values, arrays and objects of them.
  //
  // WARNING: must match spell_value/1 on the server (carry.ex).
  static #spellValue(value) {
    if (value === null) {
      return "null";
    }

    switch (typeof value) {
      case "boolean":
        return $.#spellString(String(value));

      case "number":
        return $.#spellNumber(value);

      case "string":
        return $.#spellString(value);
    }

    if (Array.isArray(value)) {
      return `[${value.map($.#spellValue).join(",")}]`;
    }

    if ($.#isValueObject(value)) {
      return $.#spellObject(
        Object.entries(value).map(([key, member]) => [
          key,
          $.#spellValue(member),
        ]),
      );
    }

    return $.#spellUnknown(value);
  }
}

const $ = QuerySpelling;
