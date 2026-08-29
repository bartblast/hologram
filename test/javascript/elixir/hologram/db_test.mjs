"use strict";

import {assert, defineRuntimeGlobals} from "../../support/helpers.mjs";

import Batches from "../../../../assets/js/batches.mjs";
import Elixir_Hologram_DB from "../../../../assets/js/elixir/hologram/db.mjs";
import Elixir_Hologram_Query from "../../../../assets/js/elixir/hologram/query.mjs";
import HologramBoxedError from "../../../../assets/js/errors/boxed_error.mjs";
import LocalDatabase from "../../../../assets/js/local_database.mjs";
import Model from "../../../../assets/js/model.mjs";
import Type from "../../../../assets/js/type.mjs";

defineRuntimeGlobals();

// Mirrors what test/elixir/hologram/db_test.exs asks of read/1 and read/2, against the client's
// own database rather than Postgres. The refusals are the server's, word for word.
describe("Elixir_Hologram_DB", () => {
  const TASK = "MyApp.Task";

  const task = Type.alias(TASK);

  const count = Elixir_Hologram_Query["count/1"];
  const filter = Elixir_Hologram_Query["filter/2"];
  const one = Elixir_Hologram_Query["one/1"];
  const read = Elixir_Hologram_DB["read/1"];
  const readById = Elixir_Hologram_DB["read/2"];

  const ID_1 = "018f0000-0000-7000-8000-000000000001";
  const ID_2 = "018f0000-0000-7000-8000-000000000002";

  const field = (struct, name) =>
    struct.data[Type.encodeMapKey(Type.atom(name))][1];

  const predicates = (pairs) =>
    Type.list(
      pairs.map(([name, value]) => Type.tuple([Type.atom(name), value])),
    );

  const row = (id, overrides = {}) => ({
    done: false,
    id,
    title: "Draft copy",
    ...overrides,
  });

  beforeEach(() => {
    globalThis.Hologram.sync = {
      model: {
        [TASK]: {
          attributes: {done: "boolean", id: "uuid", title: "string"},
          constraints: {},
          defaults: {},
          enumValues: {},
          frameworkAttributes: [],
          relationships: {},
          serverOnly: [],
        },
      },
    };

    Batches.reset();
    LocalDatabase.actorUserId = null;
    LocalDatabase.reset();
    Model.reset();
  });

  afterEach(() => {
    Batches.reset();
  });

  describe("read/1", () => {
    it("answers every row of a type as a list of structs", () => {
      LocalDatabase.putRow(TASK, row(ID_1));
      LocalDatabase.putRow(TASK, row(ID_2, {title: "Ship it"}));

      const result = read(task);

      assert.equal(result.data.length, 2);
    });

    it("answers an empty list when the type holds nothing", () => {
      assert.deepStrictEqual(read(task), Type.list([]));
    });

    it("answers the rows a filter admits", () => {
      LocalDatabase.putRow(TASK, row(ID_1));
      LocalDatabase.putRow(TASK, row(ID_2, {done: true}));

      const result = read(
        filter(task, predicates([["done", Type.boolean(true)]])),
      );

      assert.equal(result.data.length, 1);
      assert.deepStrictEqual(field(result.data[0], "id"), Type.bitstring(ID_2));
    });

    it("answers one struct for a single-result query", () => {
      LocalDatabase.putRow(TASK, row(ID_1));

      const result = read(
        one(filter(task, predicates([["id", Type.bitstring(ID_1)]]))),
      );

      assert.deepStrictEqual(
        field(result, "title"),
        Type.bitstring("Draft copy"),
      );
    });

    it("answers nil for a single-result query matching nothing", () => {
      assert.deepStrictEqual(read(one(task)), Type.nil());
    });

    it("answers a number for a counting query", () => {
      LocalDatabase.putRow(TASK, row(ID_1));
      LocalDatabase.putRow(TASK, row(ID_2));

      assert.deepStrictEqual(read(count(task)), Type.integer(2));
    });

    // The whole point of reading through the overlay: an action writes on one line and reads it
    // back on the next, before anything has been sent.
    it("reads a row a pending write created", () => {
      const batch = Batches.open("todos");

      batch.append({
        data: {done: false, title: "Mine, unsent"},
        id: ID_1,
        op: "create",
        stamp: 1_798_246_400_125_952,
        type: TASK,
      });

      const result = read(one(task));

      assert.deepStrictEqual(
        field(result, "title"),
        Type.bitstring("Mine, unsent"),
      );
    });

    it("does not read a row a pending write deleted", () => {
      LocalDatabase.putRow(TASK, row(ID_1));

      const batch = Batches.open("todos");

      batch.append({id: ID_1, op: "delete", stamp: 1, type: TASK});

      assert.deepStrictEqual(read(task), Type.list([]));
    });

    // The one thing the acting user is carried for: a predicate that NAMES them. The client
    // evaluates no read policies - it holds only rows the server already let it have - so this is
    // the whole of what actorUserId does here.
    it("binds a predicate naming the acting user", () => {
      LocalDatabase.actorUserId = ID_2;
      LocalDatabase.putRow(TASK, row(ID_1));
      LocalDatabase.putRow(TASK, row(ID_2, {title: "Mine"}));

      const result = read(
        filter(task, predicates([["id", Type.tuple([Type.atom("actor")])]])),
      );

      assert.equal(result.data.length, 1);

      assert.deepStrictEqual(
        field(result.data[0], "title"),
        Type.bitstring("Mine"),
      );
    });

    it("raises for a query term carrying a placeholder", () => {
      const placeholder = Type.struct("Hologram.Query.Placeholder", [
        [Type.atom("name"), Type.atom("wanted")],
      ]);

      assert.throw(
        () => read(filter(task, predicates([["title", placeholder]]))),
        HologramBoxedError,
        "cannot read a query term containing placeholders - placeholder :wanted has no value: directly executed queries embed concrete runtime values, placeholders exist only in compiler-registered queries",
      );
    });
  });

  describe("read/2", () => {
    it("answers the row with the given id", () => {
      LocalDatabase.putRow(TASK, row(ID_1));

      const result = readById(task, Type.bitstring(ID_1));

      assert.deepStrictEqual(field(result, "id"), Type.bitstring(ID_1));
    });

    it("answers nil when no row has the given id", () => {
      LocalDatabase.putRow(TASK, row(ID_1));

      assert.deepStrictEqual(readById(task, Type.bitstring(ID_2)), Type.nil());
    });

    it("reads a row a pending write created", () => {
      const batch = Batches.open("todos");

      batch.append({
        data: {done: false, title: "Mine, unsent"},
        id: ID_1,
        op: "create",
        stamp: 1_798_246_400_125_952,
        type: TASK,
      });

      assert.deepStrictEqual(
        field(readById(task, Type.bitstring(ID_1)), "title"),
        Type.bitstring("Mine, unsent"),
      );
    });

    it("raises when the id is not a canonical entity id", () => {
      assert.throw(
        () => readById(task, Type.bitstring("nope")),
        HologramBoxedError,
        'invalid id "nope" - entity ids are canonical lowercase 8-4-4-4-12 UUID strings',
      );

      assert.throw(
        () => readById(task, Type.bitstring(ID_1.toUpperCase())),
        HologramBoxedError,
        `invalid id "${ID_1.toUpperCase()}" - entity ids are canonical lowercase 8-4-4-4-12 UUID strings`,
      );
    });

    it("raises when the first argument is not an entity type module", () => {
      assert.throw(
        () => readById(filter(task, predicates([])), Type.bitstring(ID_1)),
        HologramBoxedError,
        "is not an entity type module - a by-id read takes the entity type, a query term is read with read/1",
      );
    });

    // A module name this build carries no entity for reaches the second half of the check, where
    // a query term is refused by the first.
    it("raises when the module names no entity type this build carries", () => {
      assert.throw(
        () => readById(Type.alias("MyApp.Nope"), Type.bitstring(ID_1)),
        HologramBoxedError,
        "MyApp.Nope is not an entity type module - a by-id read takes the entity type, a query term is read with read/1",
      );
    });
  });
});
