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
  const PROJECT = "MyApp.Project";
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
        [PROJECT]: {
          attributes: {id: "uuid", name: "string"},
          relationships: {
            owner: {toMany: false, type: "MyApp.User"},
            tasks: {toMany: true, type: TASK},
          },
          serverOnly: [],
        },
        [TASK]: {
          attributes: {
            created_at: "datetime",
            done: "boolean",
            id: "uuid",
            status: "enum",
            title: "string",
          },
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

  describe("order_by/2", () => {
    const orderBy = Elixir_Hologram_Query["order_by/2"];

    it("defaults a bare attribute name to ascending", () => {
      assert.deepStrictEqual(orderBy(task, Type.atom("title")).orderBy, [
        ["title", "asc"],
      ]);
    });

    it("defaults list entries to ascending", () => {
      const spec = Type.list([Type.atom("title"), Type.atom("done")]);

      assert.deepStrictEqual(orderBy(task, spec).orderBy, [
        ["title", "asc"],
        ["done", "asc"],
      ]);
    });

    it("accepts a keyword spec with directions", () => {
      const spec = Type.list([
        Type.tuple([Type.atom("title"), Type.atom("desc")]),
      ]);

      assert.deepStrictEqual(orderBy(task, spec).orderBy, [["title", "desc"]]);
    });

    it("accepts a mixed list of names and direction tuples", () => {
      const spec = Type.list([
        Type.atom("done"),
        Type.tuple([Type.atom("title"), Type.atom("desc")]),
      ]);

      assert.deepStrictEqual(orderBy(task, spec).orderBy, [
        ["done", "asc"],
        ["title", "desc"],
      ]);
    });

    it("appends to prior ordering", () => {
      const query = orderBy(
        orderBy(task, Type.atom("done")),
        Type.atom("title"),
      );

      assert.deepStrictEqual(query.orderBy, [
        ["done", "asc"],
        ["title", "asc"],
      ]);
    });

    it("orders by a system attribute", () => {
      assert.deepStrictEqual(orderBy(task, Type.atom("created_at")).orderBy, [
        ["created_at", "asc"],
      ]);
    });

    it("raises on a non-atom spec", () => {
      assert.throw(
        () => orderBy(task, Type.integer(123)),
        HologramBoxedError,
        "order_by spec must be an attribute name or a list, got: 123",
      );
    });

    it("raises on an invalid entry", () => {
      assert.throw(
        () => orderBy(task, Type.list([Type.integer(123)])),
        HologramBoxedError,
        "invalid order_by entry 123 - use an attribute name or an {attribute, :asc | :desc} tuple",
      );
    });

    it("raises on an invalid direction", () => {
      const spec = Type.list([
        Type.tuple([Type.atom("title"), Type.atom("down")]),
      ]);

      assert.throw(
        () => orderBy(task, spec),
        HologramBoxedError,
        "invalid direction :down for attribute :title - use :asc or :desc",
      );
    });

    it("raises on a relationship name", () => {
      assert.throw(
        () => orderBy(Type.alias(PROJECT), Type.atom("tasks")),
        HologramBoxedError,
        ":tasks is a relationship in MyApp.Project - only attributes can be ordered",
      );
    });

    // The two tiers disagree on what order enum values are in, so neither orders by them.
    it("raises on an enum attribute", () => {
      assert.throw(
        () => orderBy(task, Type.atom("status")),
        HologramBoxedError,
        "ordering by enum attributes is not supported - attribute :status in MyApp.Task has type :enum",
      );
    });

    // A reference field is not among the attributes on either tier - a relationship is followed,
    // never ordered by.
    it("raises on a to-one reference field", () => {
      assert.throw(
        () => orderBy(Type.alias(PROJECT), Type.atom("owner_id")),
        HologramBoxedError,
        "unknown attribute :owner_id in MyApp.Project - known attributes: :id, :name",
      );
    });

    it("raises on an unknown attribute", () => {
      assert.throw(
        () => orderBy(task, Type.atom("x")),
        HologramBoxedError,
        "unknown attribute :x in MyApp.Task - known attributes: :created_at, :done, :id, :status, :title",
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
