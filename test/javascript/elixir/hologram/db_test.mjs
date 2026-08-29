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
  const ITEM = "MyApp.Item";
  const NOTIFY = "MyApp.Jobs.Notify";
  const ROLE_GRANT = "Hologram.Auth.RoleGrant";
  const TASK = "MyApp.Task";

  const task = Type.alias(TASK);

  const authorize = Elixir_Hologram_Query["authorize/2"];
  const count = Elixir_Hologram_Query["count/1"];
  const addRelationship = Elixir_Hologram_Query["add_relationship/3"];
  const create = Elixir_Hologram_DB["create/1"];
  const decrement = Elixir_Hologram_Query["decrement/3"];
  const increment = Elixir_Hologram_Query["increment/3"];
  const putAttribute = Elixir_Hologram_Query["put_attribute/2"];
  const update = Elixir_Hologram_DB["update/1"];
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
        // A counter with a floor, so a move can be judged on the value it ARRIVES at.
        [ITEM]: {
          attributes: {id: "uuid", stock: "integer"},
          constraints: {stock: {min: Type.integer(0)}},
          defaults: {},
          enumValues: {},
          frameworkAttributes: [],
          relationships: {},
          serverOnly: [],
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
          // A to-many adds no settable field, so the entries a create sends are unchanged by it.
          relationships: {
            tags: {optional: true, toMany: true, type: "MyApp.Tag"},
          },
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

    // What C7a proves is the ENTRY the batch carries; these prove the same write is readable
    // through the database's own getters the moment it is made, which is the seam the whole
    // issue turns on. No production code stands between them - the batch is in the overlay from
    // the moment the action opened it.
    it("puts the row in the database, spelled the way the wire spells one", () => {
      create(struct(TASK, {done: false, title: "Łódź"}));

      assert.deepStrictEqual(LocalDatabase.getRow(TASK, ID_1), {
        created_at: TIMESTAMP,
        done: false,
        id: ID_1,
        title: "Łódź",
        title_sort: "lodz",
        updated_at: TIMESTAMP,
        $revisions: {done: STAMP, title: STAMP},
      });
    });

    it("leaves the row the server sent untouched underneath", () => {
      create(struct(TASK, {done: false, title: "alpha"}));

      assert.isNull(LocalDatabase.baseRow(TASK, ID_1));
    });

    it("lists the row through a read on the next line", () => {
      create(struct(TASK, {done: false, title: "alpha"}));

      const result = read(task);

      assert.equal(result.data.length, 1);

      assert.deepStrictEqual(
        field(result.data[0], "title"),
        Type.bitstring("alpha"),
      );
    });

    it("keeps the row once the action's batch is sealed", () => {
      create(struct(TASK, {done: false, title: "alpha"}));
      Batches.close();

      assert.isNotNull(LocalDatabase.getRow(TASK, ID_1));
    });

    it("takes the row away when the action's writes are discarded", () => {
      create(struct(TASK, {done: false, title: "alpha"}));
      Batches.discard();

      assert.isNull(LocalDatabase.getRow(TASK, ID_1));
      assert.deepStrictEqual(read(task), Type.list([]));
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

  describe("update/1", () => {
    const NOW_MS = 1_756_100_000_123;
    const STAMP = NOW_MS * 1024;

    let timers;

    beforeEach(() => {
      timers = sinon.useFakeTimers(NOW_MS);
      Batches.open("todos");

      LocalDatabase.putRow(TASK, {
        done: false,
        id: ID_1,
        title: "Draft copy",
        $revisions: {done: 10, title: 11},
      });
    });

    afterEach(() => {
      timers.restore();
    });

    const held = () => Model.box(TASK, LocalDatabase.getRow(TASK, ID_1));

    const pairs = (values) =>
      Type.list(
        values.map(([name, value]) => Type.tuple([Type.atom(name), value])),
      );

    it("appends one entry for the values it puts", () => {
      update(
        putAttribute(held(), pairs([["title", Type.bitstring("Ship it")]])),
      );

      assert.deepStrictEqual(Batches.current().writes, [
        {
          based_on: {title: 11},
          claim: null,
          data: {title: "Ship it"},
          id: ID_1,
          op: "update",
          stamp: STAMP,
          type: TASK,
        },
      ]);
    });

    it("says it was based on the revisions it saw, for the fields it sets", () => {
      update(
        putAttribute(
          held(),
          pairs([
            ["done", Type.boolean(true)],
            ["title", Type.bitstring("x")],
          ]),
        ),
      );

      assert.deepStrictEqual(Batches.current().writes[0].based_on, {
        done: 10,
        title: 11,
      });
    });

    it("answers :ok", () => {
      assert.deepStrictEqual(
        update(putAttribute(held(), pairs([["title", Type.bitstring("x")]]))),
        Type.atom("ok"),
      );
    });

    it("carries no deltas key for an update that only puts", () => {
      update(putAttribute(held(), pairs([["title", Type.bitstring("x")]])));

      assert.notProperty(Batches.current().writes[0], "deltas");
    });

    it("appends the edges it records, in one order", () => {
      const entity = addRelationship(
        addRelationship(held(), Type.atom("tags"), Type.bitstring("g2")),
        Type.atom("tags"),
        Type.bitstring("g1"),
      );

      update(entity);

      assert.deepStrictEqual(
        Batches.current().writes.map((write) => [write.op, write.target_id]),
        [
          ["add_relationship", "g1"],
          ["add_relationship", "g2"],
        ],
      );
    });

    it("carries the claim a stage recorded on every entry it appends", () => {
      const entity = authorize(
        addRelationship(
          putAttribute(held(), pairs([["title", Type.bitstring("x")]])),
          Type.atom("tags"),
          Type.bitstring("g1"),
        ),
        Type.atom("publish"),
      );

      update(entity);

      for (const write of Batches.current().writes) {
        assert.deepStrictEqual(write.claim, ["authorize", "publish"]);
      }
    });

    it("answers a refusal from the declarations and appends nothing", () => {
      const result = update(
        putAttribute(held(), pairs([["title", Type.nil()]])),
      );

      assert.deepStrictEqual(result.data[0], Type.atom("error"));
      assert.deepStrictEqual(Batches.current().writes, []);
    });

    it("appends one entry carrying only the amounts it moves", () => {
      LocalDatabase.putRow(ITEM, {id: ID_2, stock: 3, $revisions: {stock: 12}});

      const item = Model.box(ITEM, LocalDatabase.getRow(ITEM, ID_2));

      update(increment(item, Type.atom("stock"), Type.integer(2)));

      assert.deepStrictEqual(Batches.current().writes, [
        {
          claim: null,
          deltas: {stock: 2},
          id: ID_2,
          op: "update",
          stamp: STAMP,
          type: ITEM,
        },
      ]);
    });

    // A delta is never merged, so there is nothing for it to be based on - and the entry says so
    // by carrying neither data nor based_on.
    it("says a move was based on nothing", () => {
      LocalDatabase.putRow(ITEM, {id: ID_2, stock: 3, $revisions: {stock: 12}});

      const item = Model.box(ITEM, LocalDatabase.getRow(ITEM, ID_2));

      update(increment(item, Type.atom("stock"), Type.integer(2)));

      assert.notProperty(Batches.current().writes[0], "based_on");
      assert.notProperty(Batches.current().writes[0], "data");
    });

    it("answers a refusal judging a move on the value it arrives at", () => {
      LocalDatabase.putRow(ITEM, {id: ID_2, stock: 0, $revisions: {stock: 12}});

      const item = Model.box(ITEM, LocalDatabase.getRow(ITEM, ID_2));

      const result = update(
        decrement(item, Type.atom("stock"), Type.integer(1)),
      );

      assert.deepStrictEqual(result.data[0], Type.atom("error"));

      assert.deepStrictEqual(
        result.data[1],
        Type.map([
          [
            Type.atom("stock"),
            Type.list([Type.tuple([Type.atom("min"), Type.integer(0)])]),
          ],
        ]),
      );

      assert.deepStrictEqual(Batches.current().writes, []);
    });

    // What the entries carry is asserted above; these read the same write back through the
    // database, which is what an action does on its next line.
    it("shows the value it put, at the revision it set", () => {
      update(
        putAttribute(held(), pairs([["title", Type.bitstring("Ship it")]])),
      );

      const row = LocalDatabase.getRow(TASK, ID_1);

      assert.equal(row.title, "Ship it");
      assert.equal(row.title_sort, "ship it");
      assert.deepStrictEqual(row.$revisions, {done: 10, title: STAMP});
    });

    it("leaves the row the server sent untouched underneath", () => {
      update(
        putAttribute(held(), pairs([["title", Type.bitstring("Ship it")]])),
      );

      assert.equal(LocalDatabase.baseRow(TASK, ID_1).title, "Draft copy");
      assert.equal(LocalDatabase.baseRow(TASK, ID_1).$revisions.title, 11);
    });

    it("shows a moved counter moved, its revision left alone", () => {
      LocalDatabase.putRow(ITEM, {id: ID_2, stock: 3, $revisions: {stock: 12}});

      const item = Model.box(ITEM, LocalDatabase.getRow(ITEM, ID_2));

      update(increment(item, Type.atom("stock"), Type.integer(2)));

      const row = LocalDatabase.getRow(ITEM, ID_2);

      assert.equal(row.stock, 5);
      assert.equal(row.$revisions.stock, 12);
    });

    // The chain D1 rests on: a second write to a column says it was based on what the FIRST one
    // stored, because the first one wrote its stamp into the row this one read. Nothing is
    // predicted - based_on is simply what the local row holds.
    it("bases a second write to a column on the stamp the first one set", () => {
      update(putAttribute(held(), pairs([["title", Type.bitstring("First")]])));
      update(
        putAttribute(held(), pairs([["title", Type.bitstring("Second")]])),
      );

      const [first, second] = Batches.current().writes;

      assert.deepStrictEqual(first.based_on, {title: 11});
      assert.deepStrictEqual(second.based_on, {title: first.stamp});
      assert.equal(LocalDatabase.getRow(TASK, ID_1).title, "Second");
    });

    it("shows the edges it recorded", () => {
      update(addRelationship(held(), Type.atom("tags"), Type.bitstring("g1")));

      assert.deepStrictEqual(
        LocalDatabase.getTargetIds(TASK, "tags", ID_1),
        new Set(["g1"]),
      );
    });

    it("takes the change away when the action's writes are discarded", () => {
      update(
        putAttribute(held(), pairs([["title", Type.bitstring("Ship it")]])),
      );

      Batches.discard();

      assert.equal(LocalDatabase.getRow(TASK, ID_1).title, "Draft copy");
    });

    it("raises when the struct records no change", () => {
      assert.throw(
        () => update(held()),
        HologramBoxedError,
        "update takes recorded changes - put values with put_attribute, move counters with increment or decrement, and edges with add_relationship or delete_relationship. A field set directly on the struct is not recorded: writing the whole struct would overwrite concurrent changes to fields you didn't touch.",
      );
    });

    it("raises for a row this client does not hold", () => {
      const absent = Model.box(TASK, {done: false, id: ID_2, title: "x"});

      assert.throw(
        () =>
          update(putAttribute(absent, pairs([["title", Type.bitstring("y")]]))),
        HologramBoxedError,
        `cannot update MyApp.Task - no entity with id "${ID_2}"`,
      );
    });

    it("raises for a put naming a value the client was never shown", () => {
      LocalDatabase.putRow(DOC, {id: ID_2, title: "x"});

      const doc = Model.box(DOC, LocalDatabase.getRow(DOC, ID_2));

      assert.throw(
        () =>
          update(
            putAttribute(doc, pairs([["api_token", Type.bitstring("s")]])),
          ),
        HologramBoxedError,
        ":api_token of MyApp.Doc is server-only - a browser cannot write it, set it in a command or a job",
      );
    });

    it("raises when no action is open", () => {
      const entity = putAttribute(
        held(),
        pairs([["title", Type.bitstring("x")]]),
      );

      Batches.reset();

      assert.throw(
        () => update(entity),
        HologramBoxedError,
        "update was called outside an action - a client write happens inside an action, whose writes ship together when it returns",
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
