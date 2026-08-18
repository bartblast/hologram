"use strict";

import {assert, defineRuntimeGlobals} from "../../support/helpers.mjs";

import Elixir_Hologram_Query from "../../../../assets/js/elixir/hologram/query.mjs";
import HologramBoxedError from "../../../../assets/js/errors/boxed_error.mjs";
import Type from "../../../../assets/js/type.mjs";

defineRuntimeGlobals();

// Mirrors the corresponding describes of test/elixir/hologram/query_test.exs, case for case and
// with the same raise messages. What differs is the term: these stages build the plain term the
// client's kernel evaluates, where the Elixir ones build a boxed map keyed by atoms.
describe("Elixir_Hologram_Query", () => {
  const TASK = "MyApp.Task";

  const task = Type.alias(TASK);

  const count = Elixir_Hologram_Query["count/1"];
  const limit = Elixir_Hologram_Query["limit/2"];
  const offset = Elixir_Hologram_Query["offset/2"];
  const one = Elixir_Hologram_Query["one/1"];

  const freshTerm = {
    cardinality: "set",
    entity: TASK,
    filter: [],
    include: {},
    limit: null,
    offset: null,
    orderBy: [],
  };

  beforeEach(() => {
    globalThis.Hologram.sync = {
      model: {
        [TASK]: {
          attributes: {done: "boolean", id: "uuid", title: "string"},
          relationships: {},
          serverOnly: [],
        },
      },
      orderedStringPairs: [],
    };
  });

  describe("count/1", () => {
    it("marks the query as counting", () => {
      assert.deepStrictEqual(count(task), {...freshTerm, cardinality: "count"});
    });

    it("composes with other stages", () => {
      const query = count(limit(task, Type.integer(50)));

      assert.equal(query.cardinality, "count");
      assert.equal(query.limit, 50);
    });

    it("raises when cardinality is already marked", () => {
      assert.throw(
        () => count(one(task)),
        HologramBoxedError,
        "cardinality is already set to :one",
      );
    });
  });

  describe("limit/2", () => {
    it("accepts zero", () => {
      assert.equal(limit(task, Type.integer(0)).limit, 0);
    });

    it("composes with other stages", () => {
      const query = limit(offset(task, Type.integer(20)), Type.integer(50));

      assert.equal(query.offset, 20);
      assert.equal(query.limit, 50);
    });

    it("sets the limit", () => {
      assert.deepStrictEqual(limit(task, Type.integer(50)), {
        ...freshTerm,
        limit: 50,
      });
    });

    it("raises on a negative limit", () => {
      assert.throw(
        () => limit(task, Type.integer(-5)),
        HologramBoxedError,
        "limit must be a non-negative integer, got: -5",
      );
    });

    it("raises on a non-integer limit", () => {
      assert.throw(
        () => limit(task, Type.float(5.0)),
        HologramBoxedError,
        "limit must be a non-negative integer, got: 5.0",
      );
    });

    it("raises when the limit is already set", () => {
      assert.throw(
        () => limit(limit(task, Type.integer(50)), Type.integer(100)),
        HologramBoxedError,
        "limit is already set to 50",
      );
    });
  });

  describe("offset/2", () => {
    it("sets the offset", () => {
      assert.deepStrictEqual(offset(task, Type.integer(20)), {
        ...freshTerm,
        offset: 20,
      });
    });

    it("raises on a negative offset", () => {
      assert.throw(
        () => offset(task, Type.integer(-5)),
        HologramBoxedError,
        "offset must be a non-negative integer, got: -5",
      );
    });

    it("raises when the offset is already set", () => {
      assert.throw(
        () => offset(offset(task, Type.integer(20)), Type.integer(40)),
        HologramBoxedError,
        "offset is already set to 20",
      );
    });
  });

  describe("one/1", () => {
    it("marks the query as single-result", () => {
      assert.deepStrictEqual(one(task), {...freshTerm, cardinality: "one"});
    });

    it("raises when cardinality is already marked", () => {
      assert.throw(
        () => one(count(task)),
        HologramBoxedError,
        "cardinality is already set to :count",
      );
    });
  });

  // A stage takes the module a query starts from or the term the stage before it returned, and
  // the term it hands on is what the kernel reads - so what a stage refuses is what the client
  // could not have answered anyway.
  describe("the query a stage starts from", () => {
    it("carries the stages already applied", () => {
      const query = offset(limit(task, Type.integer(5)), Type.integer(10));

      assert.equal(query.limit, 5);
      assert.equal(query.offset, 10);
      assert.equal(query.entity, TASK);
    });

    it("raises for a value that is neither a module nor a term", () => {
      assert.throw(
        () => limit(Type.bitstring("MyApp.Task"), Type.integer(5)),
        HologramBoxedError,
        '"MyApp.Task" is not an entity type module or a query term - a query starts from a module with the "use Hologram.Entity" directive',
      );
    });

    // A type whose rows never reach a client is one this side cannot answer for, so it is
    // refused where the server would refuse a module that is not an entity type at all.
    it("raises for a type this build never told the client about", () => {
      assert.throw(
        () => limit(Type.alias("MyApp.Unknown"), Type.integer(5)),
        HologramBoxedError,
        "MyApp.Unknown is not an entity type module or a query term",
      );
    });
  });
});
