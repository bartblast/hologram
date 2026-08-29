"use strict";

import {assert, defineRuntimeGlobals, sinon} from "../../support/helpers.mjs";

import Batches from "../../../../assets/js/batches.mjs";
import Clock from "../../../../assets/js/clock.mjs";
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
  const DOC = "MyApp.Doc";
  const NOTIFY = "MyApp.Jobs.Notify";
  const ROLE_GRANT = "Hologram.Auth.RoleGrant";
  const TASK = "MyApp.Task";

  const task = Type.alias(TASK);

  const authorize = Elixir_Hologram_Query["authorize/2"];
  const count = Elixir_Hologram_Query["count/1"];
  const create = Elixir_Hologram_DB["create/1"];
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
        // A type carrying a server-only attribute, which the WRITE refuses by name rather than
        // validation refusing its value.
        [DOC]: {
          attributes: {
            api_token: "string",
            created_at: "datetime",
            id: "uuid",
            title: "string",
            updated_at: "datetime",
          },
          constraints: {api_token: {optional: true}},
          defaults: {},
          enumValues: {},
          frameworkAttributes: [],
          relationships: {},
          serverOnly: ["api_token"],
        },
        // A job type - the three attributes its framework fills are what tells one apart here.
        [NOTIFY]: {
          attributes: {
            actor_id: "uuid",
            error: "string",
            id: "uuid",
            reason: "string",
            status: "string",
          },
          constraints: {},
          defaults: {},
          enumValues: {},
          frameworkAttributes: ["actor_id", "error", "status"],
          relationships: {},
          serverOnly: [],
        },
        [ROLE_GRANT]: {
          attributes: {id: "uuid", role: "string"},
          constraints: {},
          defaults: {},
          enumValues: {},
          frameworkAttributes: [],
          relationships: {},
          serverOnly: [],
        },
        [TASK]: {
          attributes: {
            created_at: "datetime",
            done: "boolean",
            id: "uuid",
            title: "string",
            updated_at: "datetime",
          },
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
    Clock.reset();
    LocalDatabase.actorUserId = null;
    LocalDatabase.reset();
    Model.reset();
  });

  afterEach(() => {
    Batches.reset();
  });

  describe("create/1", () => {
    const NOW_MS = 1_756_100_000_123;
    const STAMP = NOW_MS * 1024;
    const TIMESTAMP = "2025-08-25T05:33:20.123000Z";

    let timers;

    beforeEach(() => {
      timers = sinon.useFakeTimers(NOW_MS);
      Batches.open("todos");
    });

    afterEach(() => {
      timers.restore();
    });

    const struct = (entityType, fields) =>
      Model.box(entityType, {id: ID_1, ...fields});

    it("appends one write entry spelling the row the wire carries", () => {
      create(struct(TASK, {done: false, title: "alpha"}));

      assert.deepStrictEqual(Batches.current().writes, [
        {
          claim: null,
          data: {done: false, title: "alpha"},
          id: ID_1,
          op: "create",
          stamp: STAMP,
          type: TASK,
        },
      ]);
    });

    it("carries the claim a stage recorded", () => {
      const claimed = authorize(
        struct(TASK, {done: false, title: "alpha"}),
        Type.atom("publish"),
      );

      create(claimed);

      assert.deepStrictEqual(Batches.current().writes[0].claim, [
        "authorize",
        "publish",
      ]);
    });

    it("answers the row as it now stands", () => {
      const result = create(struct(TASK, {done: false, title: "alpha"}));

      assert.deepStrictEqual(result.data[0], Type.atom("ok"));

      const stored = result.data[1];

      assert.deepStrictEqual(field(stored, "title"), Type.bitstring("alpha"));

      assert.deepStrictEqual(
        field(stored, "created_at"),
        Model.boxValue(TIMESTAMP, "datetime"),
      );

      assert.deepStrictEqual(
        field(stored, "updated_at"),
        field(stored, "created_at"),
      );
    });

    it("answers a row whose every settable field takes the write's stamp", () => {
      const result = create(struct(TASK, {done: false, title: "alpha"}));
      const metadata = field(result.data[1], "__meta__");

      assert.deepStrictEqual(
        field(metadata, "revisions"),
        Type.map([
          [Type.atom("done"), Type.integer(STAMP)],
          [Type.atom("title"), Type.integer(STAMP)],
        ]),
      );
    });

    it("answers a row carrying nothing of what it was asked to do", () => {
      const claimed = authorize(
        struct(TASK, {done: false, title: "alpha"}),
        Type.atom("publish"),
      );

      const metadata = field(create(claimed).data[1], "__meta__");

      assert.deepStrictEqual(field(metadata, "claim"), Type.nil());
      assert.deepStrictEqual(field(metadata, "attribute_ops"), Type.map([]));
      assert.deepStrictEqual(field(metadata, "stamp"), Type.nil());
    });

    it("answers a refusal from the declarations and appends nothing", () => {
      const result = create(struct(TASK, {done: false, title: Type.nil()}));

      assert.deepStrictEqual(result.data[0], Type.atom("error"));
      assert.deepStrictEqual(Batches.current().writes, []);
    });

    // Model.box renders a server-only attribute as the sentinel whatever the row holds, so the
    // value a browser must not write has to be put on the struct the way app code would - by
    // constructing it, which is what Entity.new does and what a form would hand the verb.
    const withServerOnlyValue = () => {
      const held = struct(DOC, {title: "x"});
      const key = Type.encodeMapKey(Type.atom("api_token"));

      held.data[key] = [Type.atom("api_token"), Type.bitstring("secret")];

      return held;
    };

    it("raises for a value the client was never shown", () => {
      assert.throw(
        () => create(withServerOnlyValue()),
        HologramBoxedError,
        ":api_token of MyApp.Doc is server-only - a browser cannot write it, set it in a command or a job",
      );
    });

    it("passes over a server-only attribute the row shows as a sentinel", () => {
      const held = struct(DOC, {title: "x"});

      create(held);

      assert.deepStrictEqual(Batches.current().writes[0].data, {title: "x"});
    });

    it("raises for a role grant", () => {
      assert.throw(
        () => create(struct(ROLE_GRANT, {role: "editor"})),
        HologramBoxedError,
        "role grants are written only through grant_role/revoke_role",
      );
    });

    it("raises for a job type", () => {
      assert.throw(
        () => create(struct(NOTIFY, {reason: "created"})),
        HologramBoxedError,
        "MyApp.Jobs.Notify is a job type - create it through Job.create/2, which records who enqueued it so the worker can run it as them after the transaction commits",
      );
    });

    it("raises when the value is not an entity struct", () => {
      assert.throw(
        () => create(Type.bitstring("x")),
        HologramBoxedError,
        'create takes an entity struct, got: "x"',
      );
    });

    it("raises when no action is open", () => {
      Batches.reset();

      assert.throw(
        () => create(struct(TASK, {done: false, title: "alpha"})),
        HologramBoxedError,
        "create was called outside an action - a client write happens inside an action, whose writes ship together when it returns",
      );
    });
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
