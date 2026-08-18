"use strict";

import {assert} from "./support/helpers.mjs";

import QueryKernel from "../../assets/js/query_kernel.mjs";

// Mirrors the predicate cases of test/elixir/hologram/query/interpreter_test.exs, case for case
// and in the same order - that suite proves the reference answers what the database answers, and
// this one proves the client answers what the reference does. The rows here hold what the wire
// spells rather than what Postgres returns: dates and datetimes as canonical strings.
describe("QueryKernel", () => {
  const matches = QueryKernel.matches;

  const rows = {
    ada: {id: "r1", priority: 1, username: "ada"},
    bob: {id: "r2", priority: 3, username: "bob"},
    cleo: {id: "r3", priority: null, username: "cleo"},
  };

  const matching = (filter, context) =>
    Object.values(rows)
      .filter((row) => matches(row, filter, context))
      .map((row) => row.username);

  describe("matches() - equality and membership", () => {
    it("matches a value", () => {
      assert.deepEqual(matching([["priority", "==", 3]]), ["bob"]);
    });

    // Null is a value like any other here: an unset attribute is unequal to a set one, so a
    // negated equality names the rows that never had it either.
    it("matches what is unequal, missing values included", () => {
      assert.deepEqual(matching([["priority", "!=", 3]]), ["ada", "cleo"]);
    });

    it("matches an unset attribute", () => {
      assert.deepEqual(matching([["priority", "==", null]]), ["cleo"]);
    });

    it("matches what is set", () => {
      assert.deepEqual(matching([["priority", "!=", null]]), ["ada", "bob"]);
    });

    it("matches membership in a list", () => {
      assert.deepEqual(matching([["priority", "in", [1, 3]]]), ["ada", "bob"]);
    });

    it("matches membership in a list naming an unset value", () => {
      assert.deepEqual(matching([["priority", "in", [null, 3]]]), [
        "bob",
        "cleo",
      ]);
    });

    // A list without null leaves the rows that have no value at all outside it, so excluding
    // the list keeps them.
    it("matches exclusion from a list, missing values included", () => {
      assert.deepEqual(matching([["priority", "not_in", [1]]]), [
        "bob",
        "cleo",
      ]);
    });

    it("matches exclusion from a list naming an unset value", () => {
      assert.deepEqual(matching([["priority", "not_in", [null, 1]]]), ["bob"]);
    });

    it("matches every predicate of a filter and no fewer", () => {
      const filter = [
        ["priority", "!=", null],
        ["username", "==", "bob"],
      ];

      assert.deepEqual(matching(filter), ["bob"]);
    });

    it("matches every row for a filter holding nothing", () => {
      assert.deepEqual(matching([]), ["ada", "bob", "cleo"]);
    });
  });

  describe("matches() - ordering comparisons", () => {
    const dated = {
      first: {
        held_at: "2026-03-01T10:00:00.000000Z",
        rating: 1.5,
        released_on: "2026-03-01",
        username: "ada",
      },
      second: {
        held_at: "2027-06-01T10:00:00.000000Z",
        rating: 4.5,
        released_on: "2027-06-01",
        username: "bob",
      },
      third: {
        held_at: null,
        rating: null,
        released_on: null,
        username: "cleo",
      },
    };

    const matchingDated = (filter) =>
      Object.values(dated)
        .filter((row) => matches(row, filter))
        .map((row) => row.username);

    it("matches values above a bound", () => {
      assert.deepEqual(matchingDated([["rating", ">", 1.5]]), ["bob"]);
    });

    it("matches values at or above a bound", () => {
      assert.deepEqual(matchingDated([["rating", ">=", 1.5]]), ["ada", "bob"]);
    });

    it("matches values below a bound", () => {
      assert.deepEqual(matchingDated([["rating", "<", 4.5]]), ["ada"]);
    });

    it("matches values at or below a bound", () => {
      assert.deepEqual(matchingDated([["rating", "<=", 4.5]]), ["ada", "bob"]);
    });

    // A canonical date is ordered by its characters, which is what makes a comparison here a
    // comparison of strings rather than a parse.
    it("compares dates", () => {
      const filter = [["released_on", ">=", "2027-01-01"]];

      assert.deepEqual(matchingDated(filter), ["bob"]);
    });

    it("compares datetimes", () => {
      const filter = [["held_at", "<", "2027-01-01T00:00:00.000000Z"]];

      assert.deepEqual(matchingDated(filter), ["ada"]);
    });

    // An ordering line has no place to put a value that is not there, so a comparison passes
    // over the rows that have none - unlike the equality family, which counts them.
    it("passes over an unset attribute, whichever way the comparison points", () => {
      assert.deepEqual(matchingDated([["rating", ">", 0]]), ["ada", "bob"]);
      assert.deepEqual(matchingDated([["rating", "<", 100]]), ["ada", "bob"]);
    });
  });

  describe("matches() - params", () => {
    it("matches against the value bound to a param", () => {
      const filter = [["priority", "==", {param: "priority"}]];
      const context = {bindings: {priority: 3}};

      assert.deepEqual(matching(filter, context), ["bob"]);
    });

    it("matches against a list bound to a param", () => {
      const filter = [["priority", "in", {param: "priorities"}]];
      const context = {bindings: {priorities: [1, 3]}};

      assert.deepEqual(matching(filter, context), ["ada", "bob"]);
    });

    it("matches against a param among the values of a list", () => {
      const filter = [["priority", "in", [{param: "priority"}, 1]]];
      const context = {bindings: {priority: 3}};

      assert.deepEqual(matching(filter, context), ["ada", "bob"]);
    });
  });

  describe("matches() - the acting user", () => {
    it("matches against who is asking", () => {
      const filter = [["id", "==", {actor: true}]];

      assert.deepEqual(matching(filter, {actorUserId: "r2"}), ["bob"]);
    });

    it("matches everything but who is asking", () => {
      const filter = [["id", "!=", {actor: true}]];

      assert.deepEqual(matching(filter, {actorUserId: "r2"}), ["ada", "cleo"]);
    });

    // There is nobody to compare against, so nothing answers - the same silence the database
    // gives a statement asking about an actor that is not there, and an unset attribute is no
    // more a match for nobody than a set one is.
    it("matches nothing for a visitor", () => {
      const filter = [["id", "==", {actor: true}]];

      assert.deepEqual(matching(filter, {actorUserId: null}), []);
    });

    // The negated form is where that silence has to be deliberate: nobody is UNEQUAL to every
    // row, so a predicate left to compare against nothing would answer with everything.
    it("matches nothing for a visitor, whichever way the predicate points", () => {
      const filter = [["id", "!=", {actor: true}]];

      assert.deepEqual(matching(filter, {actorUserId: null}), []);
    });

    it("matches nothing for a visitor a row could otherwise answer for", () => {
      const filter = [["priority", "==", {actor: true}]];

      assert.deepEqual(matching(filter, {}), []);
    });
  });
});
