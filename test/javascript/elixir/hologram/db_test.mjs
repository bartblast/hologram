"use strict";

import {
  assert,
  assertBoxedError,
  contextFixture,
  defineRuntimeGlobals,
  sinon,
} from "../../support/helpers.mjs";

import Batches from "../../../../assets/js/batches.mjs";
import Interpreter from "../../../../assets/js/interpreter.mjs";
import Bitstring from "../../../../assets/js/bitstring.mjs";
import Clock from "../../../../assets/js/clock.mjs";
import Elixir_Hologram_DB from "../../../../assets/js/elixir/hologram/db.mjs";
import Elixir_Hologram_Query_Stage from "../../../../assets/js/elixir/hologram/query/stage.mjs";
import {deriveGrantId} from "../../../../assets/js/elixir/hologram/auth.mjs";
import LocalDatabase from "../../../../assets/js/local_database.mjs";
import Model from "../../../../assets/js/model.mjs";
import Type from "../../../../assets/js/type.mjs";

defineRuntimeGlobals();

// Mirrors what test/elixir/hologram/db_test.exs asks of read/1 and read/2, against the client's
// own database rather than Postgres. The refusals are the server's, word for word.
describe("Elixir_Hologram_DB", () => {
  const DOC = "MyApp.Doc";
  const ITEM = "MyApp.Item";
  const NOTE = "MyApp.Note";
  const NOTIFY = "MyApp.Jobs.Notify";
  const ROLE_GRANT = "Hologram.Auth.RoleGrant";
  const TASK = "MyApp.Task";
  const VAULT = "MyApp.Vault";

  const task = Type.alias(TASK);

  const count = Elixir_Hologram_Query_Stage["count/1"];
  const addRelationship = Elixir_Hologram_Query_Stage["add_relationship/3"];
  const create = Elixir_Hologram_DB["create/1"];
  const rollback = Elixir_Hologram_DB["rollback/1"];
  const transaction = Elixir_Hologram_DB["transaction/2"];
  const createBang = Elixir_Hologram_DB["create!/1"];
  const deleteBang = Elixir_Hologram_DB["delete!/2"];
  const updateBang = Elixir_Hologram_DB["update!/1"];
  const updateByIdBang = Elixir_Hologram_DB["update!/3"];
  const decrement = Elixir_Hologram_Query_Stage["decrement/3"];
  const deleteEntity = Elixir_Hologram_DB["delete/1"];
  const deleteById = Elixir_Hologram_DB["delete/2"];
  const increment = Elixir_Hologram_Query_Stage["increment/3"];
  const putAttribute = Elixir_Hologram_Query_Stage["put_attribute/2"];
  const update = Elixir_Hologram_DB["update/1"];
  const updateById = Elixir_Hologram_DB["update/3"];
  const filter = Elixir_Hologram_Query_Stage["filter/2"];
  const one = Elixir_Hologram_Query_Stage["one/1"];
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
          operations: [
            "archive",
            "create",
            "delete",
            "grant_role",
            "publish",
            "read",
            "read_roles",
            "revoke_role",
            "update",
          ],
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
        // A type handing its creator a role, which a create writes into its own batch. The
        // resource type is what a grant row spells it by, and part of every grant's derived id.
        [NOTE]: {
          attributes: {id: "uuid", title: "string"},
          constraints: {},
          creatorRoles: ["owner"],
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
          // A derived field, which an update refuses by name - it has no column.
          derived: {
            tag_count: {
              definition: {value: 0},
              kind: "scalar",
              type: "integer",
              values: null,
            },
          },
          enumValues: {},
          frameworkAttributes: [],
          operations: [
            "archive",
            "create",
            "delete",
            "grant_role",
            "publish",
            "read",
            "read_roles",
            "revoke_role",
            "update",
          ],
          // A to-many adds no settable field, so the entries a create sends are unchanged by it.
          relationships: {
            tags: {optional: true, toMany: true, type: "MyApp.Tag"},
          },
          serverOnly: [],
        },
        // A counter the client is never shown, so a move naming it is refused by name the way a
        // put is - which the row alone cannot say, since it carries no column for it at all.
        [VAULT]: {
          attributes: {balance: "integer", id: "uuid"},
          constraints: {},
          defaults: {},
          enumValues: {},
          frameworkAttributes: [],
          relationships: {},
          serverOnly: ["balance"],
        },
      },
    };

    Batches.reset();
    Clock.reset();
    LocalDatabase.actorUserId = null;
    LocalDatabase.actorEntityId = null;
    LocalDatabase.reset();
    Model.reset();
  });

  afterEach(() => {
    Batches.reset();
  });

  describe("create/1", () => {
    const ACTOR = "018f0000-0000-7000-8000-00000000000a";
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
          data: {done: false, title: "alpha"},
          id: ID_1,
          op: "create",
          stamp: STAMP,
          type: TASK,
        },
      ]);
    });

    // The server judges a write by what it does, and refuses one carrying a claim.
    it("sends no claim", () => {
      create(struct(TASK, {done: false, title: "alpha"}));

      assert.notProperty(Batches.current().writes[0], "claim");
    });

    // The server writes these inside the create's own transaction, and both tiers derive a
    // grant's id from the grant itself - so the row appended here and the one the server inserts
    // are one row. They ride the create's batch, so they land together with it or not at all.
    it("appends the grants a creator takes beside the create", () => {
      LocalDatabase.actorUserId = ACTOR;
      LocalDatabase.actorEntityId = ACTOR;

      create(struct(NOTE, {title: "alpha"}));

      assert.deepStrictEqual(Batches.current().writes, [
        {
          data: {title: "alpha"},
          id: ID_1,
          op: "create",
          stamp: STAMP,
          type: NOTE,
        },
        {
          data: {
            granted_by_id: ACTOR,
            entity_id: ID_1,
            entity_type: NOTE,
            role: "owner",
            user_id: ACTOR,
          },
          id: deriveGrantId(ACTOR, NOTE, ID_1, "owner"),
          op: "create",
          stamp: STAMP + 1,
          type: ROLE_GRANT,
        },
      ]);
    });

    // creator_grants/1's nil clause, mirrored: a row made by nobody grants nobody anything.
    it("appends no grant with nobody signed in", () => {
      create(struct(NOTE, {title: "alpha"}));

      assert.deepStrictEqual(
        Batches.current().writes.map((write) => write.type),
        [NOTE],
      );
    });

    // The server takes a user id no user entity can have as no data-layer user, and grants it
    // nothing - creator_grants/1's nil clause again.
    it("appends no grant for a user id no user entity can have", () => {
      LocalDatabase.actorUserId = 7;
      LocalDatabase.actorEntityId = null;

      create(struct(NOTE, {title: "alpha"}));

      assert.deepStrictEqual(
        Batches.current().writes.map((write) => write.type),
        [NOTE],
      );
    });

    it("appends no grant for a type whose creator takes none", () => {
      LocalDatabase.actorUserId = ACTOR;
      LocalDatabase.actorEntityId = ACTOR;

      create(struct(TASK, {done: false, title: "alpha"}));

      assert.deepStrictEqual(
        Batches.current().writes.map((write) => write.type),
        [TASK],
      );
    });

    // grant_role/3's own idempotency, read off the same derived id: a grant the client holds is
    // not written a second time.
    it("appends no grant the client already holds", () => {
      LocalDatabase.actorUserId = ACTOR;
      LocalDatabase.actorEntityId = ACTOR;

      LocalDatabase.putRow(ROLE_GRANT, {
        id: deriveGrantId(ACTOR, NOTE, ID_1, "owner"),
        entity_id: ID_1,
        entity_type: NOTE,
        role: "owner",
        user_id: ACTOR,
      });

      create(struct(NOTE, {title: "alpha"}));

      assert.deepStrictEqual(
        Batches.current().writes.map((write) => write.type),
        [NOTE],
      );
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

    // The server stamps its pair when the row reaches it, so a browser's create has none yet.
    it("answers a row with no server times", () => {
      const result = create(struct(TASK, {done: false, title: "alpha"}));
      const stored = result.data[1];

      assert.deepStrictEqual(field(stored, "server_created_at"), Type.nil());
      assert.deepStrictEqual(field(stored, "server_updated_at"), Type.nil());
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
      const created = create(struct(TASK, {done: false, title: "alpha"}));
      const metadata = field(created.data[1], "__meta__");

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
      assertBoxedError(
        () => create(withServerOnlyValue()),
        "Hologram.MisuseError",
        ":api_token of MyApp.Doc is server-only - a browser cannot write it, set it in a command or a job",
      );
    });

    it("passes over a server-only attribute the row shows as a sentinel", () => {
      const held = struct(DOC, {title: "x"});

      create(held);

      assert.deepStrictEqual(Batches.current().writes[0].data, {title: "x"});
    });

    it("raises for a role grant", () => {
      assertBoxedError(
        () => create(struct(ROLE_GRANT, {role: "editor"})),
        "Hologram.MisuseError",
        "role grants are written only through grant_role/revoke_role",
      );
    });

    it("raises for a job type", () => {
      assertBoxedError(
        () => create(struct(NOTIFY, {reason: "created"})),
        "Hologram.MisuseError",
        "MyApp.Jobs.Notify is a job type - create it through Job.create/2, which records who enqueued it so the worker can run it as them after the transaction commits",
      );
    });

    it("raises when the value is not an entity struct", () => {
      assertBoxedError(
        () => create(Type.bitstring("x")),
        "Hologram.MisuseError",
        'create takes an entity struct, got: "x"',
      );
    });

    it("prints a query term passed where an entity struct goes", () => {
      const term = filter(task, predicates([["done", Type.boolean(true)]]));

      assertBoxedError(
        () => create(term),
        "Hologram.MisuseError",
        `create takes an entity struct, got: ${JSON.stringify(term)}`,
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
        server_created_at: null,
        server_updated_at: null,
        title: "Łódź",
        title$sort: "lodz",
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

      assertBoxedError(
        () => create(struct(TASK, {done: false, title: "alpha"})),
        "Hologram.MisuseError",
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

    it("marks every entry after the call's first as coming with it", () => {
      const entity = addRelationship(
        addRelationship(
          putAttribute(held(), pairs([["title", Type.bitstring("x")]])),
          Type.atom("tags"),
          Type.bitstring("g1"),
        ),
        Type.atom("tags"),
        Type.bitstring("g2"),
      );

      update(entity);

      assert.deepStrictEqual(
        Batches.current().writes.map((write) => [write.op, write.same_call]),
        [
          ["update", undefined],
          ["add_relationship", true],
          ["add_relationship", true],
        ],
      );
    });

    it("marks the edges after the first of a call that changes only edges", () => {
      const entity = addRelationship(
        addRelationship(held(), Type.atom("tags"), Type.bitstring("g1")),
        Type.atom("tags"),
        Type.bitstring("g2"),
      );

      update(entity);

      assert.deepStrictEqual(
        Batches.current().writes.map((write) => write.same_call),
        [undefined, true],
      );
    });

    it("marks nothing on a call that writes one entry", () => {
      update(addRelationship(held(), Type.atom("tags"), Type.bitstring("g1")));

      assert.notProperty(Batches.current().writes[0], "same_call");
    });

    it("leaves the first entry of the next call in the batch unmarked", () => {
      update(
        addRelationship(
          putAttribute(held(), pairs([["title", Type.bitstring("x")]])),
          Type.atom("tags"),
          Type.bitstring("g1"),
        ),
      );

      update(putAttribute(held(), pairs([["title", Type.bitstring("y")]])));

      assert.deepStrictEqual(
        Batches.current().writes.map((write) => [write.op, write.same_call]),
        [
          ["update", undefined],
          ["add_relationship", true],
          ["update", undefined],
        ],
      );
    });

    it("sends no claim on any entry", () => {
      const entity = addRelationship(
        putAttribute(held(), pairs([["title", Type.bitstring("x")]])),
        Type.atom("tags"),
        Type.bitstring("g1"),
      );

      update(entity);

      const writes = Batches.current().writes;

      assert.deepStrictEqual(
        writes.map((write) => write.op),
        ["update", "add_relationship"],
      );

      for (const write of writes) {
        assert.notProperty(write, "claim");
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
      LocalDatabase.putRow(ITEM, {
        id: ID_2,
        stock: 3,
        $revisions: {stock: 12},
      });

      const item = Model.box(ITEM, LocalDatabase.getRow(ITEM, ID_2));

      update(increment(item, Type.atom("stock"), Type.integer(2)));

      assert.deepStrictEqual(Batches.current().writes, [
        {
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
      LocalDatabase.putRow(ITEM, {
        id: ID_2,
        stock: 3,
        $revisions: {stock: 12},
      });

      const item = Model.box(ITEM, LocalDatabase.getRow(ITEM, ID_2));

      update(increment(item, Type.atom("stock"), Type.integer(2)));

      assert.notProperty(Batches.current().writes[0], "based_on");
      assert.notProperty(Batches.current().writes[0], "data");
    });

    it("answers a refusal judging a move on the value it arrives at", () => {
      LocalDatabase.putRow(ITEM, {
        id: ID_2,
        stock: 0,
        $revisions: {stock: 12},
      });

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
      assert.equal(row.title$sort, "ship it");
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
      LocalDatabase.putRow(ITEM, {
        id: ID_2,
        stock: 3,
        $revisions: {stock: 12},
      });

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
      assertBoxedError(
        () => update(held()),
        "Hologram.MisuseError",
        "update takes recorded changes - put values with put_attribute, move counters with increment or decrement, and edges with add_relationship or delete_relationship. A field set directly on the struct is not recorded: writing the whole struct would overwrite concurrent changes to fields you didn't touch.",
      );
    });

    it("prints a query term passed where an entity struct goes", () => {
      const term = filter(task, predicates([["done", Type.boolean(true)]]));

      assertBoxedError(
        () => update(term),
        "Hologram.MisuseError",
        `update takes an entity struct, got: ${JSON.stringify(term)}`,
      );
    });

    it("raises for an id that isn't a canonical UUID", () => {
      const invalid = Model.box(TASK, {
        done: false,
        id: "constructor",
        title: "x",
      });

      assertBoxedError(
        () =>
          update(
            putAttribute(invalid, pairs([["title", Type.bitstring("y")]])),
          ),
        "Hologram.MisuseError",
        'invalid id "constructor" - entity ids are canonical lowercase 8-4-4-4-12 UUID strings',
      );
    });

    it("raises for a row this client does not hold", () => {
      const absent = Model.box(TASK, {done: false, id: ID_2, title: "x"});

      assertBoxedError(
        () =>
          update(putAttribute(absent, pairs([["title", Type.bitstring("y")]]))),
        "Hologram.MisuseError",
        `cannot update MyApp.Task - no entity with id "${ID_2}"`,
      );
    });

    // The stage refuses the sentinel, so only a struct carrying a real number reaches the verb -
    // which is what Entity.new and a form both hand it.
    it("raises for a move naming a counter the client was never shown", () => {
      LocalDatabase.putRow(VAULT, {id: ID_2});

      const vault = Model.box(VAULT, LocalDatabase.getRow(VAULT, ID_2));
      const key = Type.encodeMapKey(Type.atom("balance"));

      vault.data[key] = [Type.atom("balance"), Type.integer(7)];

      assertBoxedError(
        () => update(increment(vault, Type.atom("balance"), Type.integer(1))),
        "Hologram.MisuseError",
        ":balance of MyApp.Vault is server-only - a browser cannot write it, set it in a command or a job",
      );
    });

    it("raises for a put naming a value the client was never shown", () => {
      LocalDatabase.putRow(DOC, {id: ID_2, title: "x"});

      const doc = Model.box(DOC, LocalDatabase.getRow(DOC, ID_2));

      assertBoxedError(
        () =>
          update(
            putAttribute(doc, pairs([["api_token", Type.bitstring("s")]])),
          ),
        "Hologram.MisuseError",
        ":api_token of MyApp.Doc is server-only - a browser cannot write it, set it in a command or a job",
      );
    });

    it("raises when no action is open", () => {
      const entity = putAttribute(
        held(),
        pairs([["title", Type.bitstring("x")]]),
      );

      Batches.reset();

      assertBoxedError(
        () => update(entity),
        "Hologram.MisuseError",
        "update was called outside an action - a client write happens inside an action, whose writes ship together when it returns",
      );
    });
  });

  // What the browser refuses by itself is what the values a call states can't pass, whatever the
  // server holds. Everything else goes to the server, which judges every write.
  describe("update/1 of rules reading the row after the change", () => {
    const ACTOR = "018f0000-0000-7000-8000-00000000000a";
    const BOARD = "MyApp.Board";
    const BOARD_1 = "018f0000-0000-7000-8000-00000000000b";
    const BOARD_2 = "018f0000-0000-7000-8000-00000000000c";
    const CARD = "MyApp.Card";
    const LABEL = "MyApp.Label";
    const LABEL_1 = "018f0000-0000-7000-8000-00000000000d";

    const rule = (overrides = {}) => ({
      predicates: [],
      to: null,
      via: null,
      ...overrides,
    });

    const newName = (name) => ({name, outer: 1});

    const datetimeInYear = (year, utcOffset = 0n) =>
      Type.struct("DateTime", [
        [Type.atom("calendar"), Type.alias("Calendar.ISO")],
        [Type.atom("day"), Type.integer(1)],
        [Type.atom("hour"), Type.integer(0)],
        [
          Type.atom("microsecond"),
          Type.tuple([Type.integer(0), Type.integer(6)]),
        ],
        [Type.atom("minute"), Type.integer(0)],
        [Type.atom("month"), Type.integer(1)],
        [Type.atom("second"), Type.integer(0)],
        [Type.atom("std_offset"), Type.integer(0)],
        [Type.atom("time_zone"), Type.bitstring("Etc/UTC")],
        [Type.atom("utc_offset"), Type.integer(utcOffset)],
        [Type.atom("year"), Type.integer(year)],
        [Type.atom("zone_abbr"), Type.bitstring("UTC")],
      ]);

    const exact = (predicates, overrides = {}) =>
      rule({new: {predicates}, ...overrides});

    const newIs = (name, value) => exact([[newName(name), "==", value]]);

    const ok = Type.atom("ok");

    let timers;

    const defineCard = (policy) => {
      const plain = (attributes) => ({
        attributes,
        constraints: {},
        defaults: {},
        enumValues: {},
        frameworkAttributes: [],
        inverses: {},
        policy: {},
        relationships: {},
        serverOnly: [],
      });

      globalThis.Hologram.sync.model[BOARD] = plain({
        archived: "boolean",
        id: "uuid",
      });

      globalThis.Hologram.sync.model[LABEL] = plain({id: "uuid"});

      globalThis.Hologram.sync.model[CARD] = {
        ...plain({
          count: "integer",
          id: "uuid",
          code: "string",
          held_at: "datetime",
          note: "string",
          rating: "float",
          status: "enum",
          title: "string",
        }),
        constraints: {
          code: {
            format: {opts: Type.list([]), source: "^\\S+$"},
            optional: true,
          },
          held_at: {optional: true},
          note: {optional: true},
          rating: {optional: true},
          title: {optional: true},
        },
        enumValues: {status: ["pending", "approved", "rejected"]},
        policy,
        relationships: {
          board: {optional: true, toMany: false, type: BOARD},
          labels: {toMany: true, type: LABEL},
        },
      };

      Model.reset();

      LocalDatabase.putRow(CARD, {
        board_id: BOARD_1,
        count: 9,
        id: ID_1,
        note: "a",
        status: "pending",
        title: "t",
      });

      LocalDatabase.putRow(BOARD, {archived: false, id: BOARD_1});
      LocalDatabase.putRow(BOARD, {archived: false, id: BOARD_2});
    };

    const card = () => Model.box(CARD, LocalDatabase.getRow(CARD, ID_1));

    const put = (values) =>
      putAttribute(
        card(),
        Type.list(
          Object.entries(values).map(([name, value]) =>
            Type.tuple([Type.atom(name), value]),
          ),
        ),
      );

    const status = (label) => ({status: Type.atom(label)});
    const note = (text) => ({note: Type.bitstring(text)});

    const denied = (fields, hint = "") =>
      `not allowed to update ${CARD} "${ID_1}" - no allow line that holds covers ${fields}${hint}`;

    const assertDenied = (values, fields, hint) =>
      assertBoxedError(
        () => update(put(values)),
        "Hologram.AccessDeniedError",
        denied(fields, hint),
      );

    const assertSent = (entity) => {
      assert.deepStrictEqual(update(entity), ok);
      assert.equal(Batches.current().writes.length, 1);
    };

    beforeEach(() => {
      timers = sinon.useFakeTimers(1_756_100_000_123);
      Batches.open("todos");
      LocalDatabase.actorEntityId = ACTOR;
    });

    afterEach(() => {
      timers.restore();
      LocalDatabase.actorEntityId = null;
    });

    describe("what the call alone decides", () => {
      it("sends a value its rule allows", () => {
        defineCard({"update:status": [newIs("status", "approved")]});

        assertSent(put(status("approved")));
      });

      it("refuses a value its rule can't allow", () => {
        defineCard({"update:status": [newIs("status", "approved")]});

        assertDenied(status("rejected"), ":status");
        assert.equal(Batches.current().writes.length, 0);
      });

      it("judges update/3 the same way", () => {
        defineCard({"update:status": [newIs("status", "approved")]});

        assertBoxedError(
          () =>
            updateById(
              Type.alias(CARD),
              Type.bitstring(ID_1),
              Type.map([[Type.atom("status"), Type.atom("rejected")]]),
            ),
          "Hologram.AccessDeniedError",
          denied(":status"),
        );
      });

      it("refuses whatever the stored row holds, when the stated value fails", () => {
        defineCard({
          "update:status": [
            exact([
              ["status", "==", "pending"],
              [newName("status"), "==", "approved"],
            ]),
          ],
        });

        assertDenied(status("rejected"), ":status");
      });

      it("refuses a rule with a role when its stated value fails", () => {
        defineCard({
          "update:status": [
            exact([[newName("status"), "==", "approved"]], {
              to: [["own", ["editor"]]],
            }),
          ],
        });

        assertDenied(status("rejected"), ":status");
      });

      it("compares two stated values", () => {
        defineCard({
          "update:note": [
            exact([[newName("note"), "==", {attribute: newName("title")}]]),
          ],
          "update:title": [rule()],
        });

        assertDenied(
          {note: Type.bitstring("x"), title: Type.bitstring("y")},
          ":note",
        );
      });

      it("reads a list of allowed values", () => {
        defineCard({
          "update:status": [
            exact([[newName("status"), "in", ["approved", "pending"]]]),
          ],
        });

        assertDenied(status("rejected"), ":status");
      });

      it("orders an enum by its declared values", () => {
        defineCard({
          "update:status": [exact([[newName("status"), ">", "pending"]])],
        });

        assertDenied(status("pending"), ":status");
      });

      it("refuses when every alternative of a disjunction fails", () => {
        defineCard({
          "update:status": [
            exact([
              {
                or: [
                  [[newName("status"), "==", "approved"]],
                  [[newName("status"), "==", "pending"]],
                ],
              },
            ]),
          ],
        });

        assertDenied(status("rejected"), ":status");
      });

      it("sends a change another line allows", () => {
        defineCard({
          "update:status": [
            newIs("status", "approved"),
            newIs("status", "rejected"),
          ],
        });

        assertSent(put(status("rejected")));
      });

      it("reads a stated empty reference", () => {
        defineCard({
          "update:board": [exact([[newName("board_id"), "!=", null]])],
        });

        assertDenied({board_id: Type.nil()}, ":board");
      });

      it("refuses a changed field no line covers", () => {
        defineCard({"update:status": [newIs("status", "approved")]});

        assertDenied({...status("approved"), ...note("x")}, ":note");
      });

      it("names every refused field, sorted", () => {
        defineCard({
          "update:note": [newIs("note", "x")],
          "update:status": [newIs("status", "approved")],
        });

        assertDenied({...status("rejected"), ...note("y")}, ":note, :status");
      });

      it("says a refused field's value was invalid", () => {
        defineCard({"update:status": [newIs("note", "x")]});

        assertDenied(
          {...note("y"), ...status("bogus")},
          ":note, :status",
          " (the value given for :status is invalid, so its rule read the stored value)",
        );
      });
    });

    describe("what only the server can decide", () => {
      it("leaves a type with no new() rule alone", () => {
        defineCard({
          "update:status": [rule({predicates: [["status", "==", "approved"]]})],
        });

        assertSent(put(status("rejected")));
      });

      it("leaves a condition on the stored value", () => {
        defineCard({
          "update:status": [
            exact([
              ["status", "==", "rejected"],
              [newName("status"), "==", "approved"],
            ]),
          ],
        });

        assertSent(put(status("approved")));
      });

      it("leaves a counter, whatever the held value makes it", () => {
        defineCard({
          "update:count": [exact([[newName("count"), "<=", 10]])],
        });

        assertSent(increment(card(), Type.atom("count"), Type.integer(5)));
      });

      it("leaves a name the call doesn't state", () => {
        defineCard({
          "update:note": [exact([[newName("title"), "==", "other"]])],
        });

        assertSent(put(note("x")));
      });

      it("leaves a role", () => {
        defineCard({
          "update:board": [exact([{hasRole: [["board"], BOARD, ["member"]]}])],
        });

        assertSent(put({board_id: Type.bitstring(BOARD_2)}));
      });

      it("leaves a role line for a visitor", () => {
        LocalDatabase.actorEntityId = null;

        defineCard({
          "update:status": [
            exact([[newName("status"), "==", "approved"]], {
              to: [["own", ["editor"]]],
            }),
          ],
        });

        assertSent(put(status("approved")));
      });

      it("leaves a delegation", () => {
        defineCard({
          "update:board": [exact([{can: ["read", ["board"]]}])],
        });

        assertSent(put({board_id: Type.bitstring(BOARD_2)}));
      });

      it("leaves a path through a related row", () => {
        defineCard({
          "update:board": [
            exact([[newName(["board", "archived"]), "==", true]]),
          ],
        });

        assertSent(put({board_id: Type.bitstring(BOARD_2)}));
      });

      it("leaves a reference to a row, which may not exist", () => {
        defineCard({
          "update:board": [exact([[newName("board_id"), "==", null]])],
        });

        assertSent(put({board_id: Type.bitstring(BOARD_2)}));
      });

      it("leaves a condition on the acting user", () => {
        defineCard({
          "update:note": [exact([[newName("note"), "==", {actor: true}]])],
        });

        assertSent(put(note("x")));
      });

      it("leaves a quantifier", () => {
        defineCard({
          "update:labels": [
            exact([
              {
                filter: [],
                quantifier: "none",
                source: {name: ["labels"], outer: 1},
              },
            ]),
          ],
        });

        LocalDatabase.putRow(LABEL, {id: LABEL_1});
        LocalDatabase.addFact(CARD, "labels", ID_1, LABEL_1);

        assertSent(
          addRelationship(card(), Type.atom("labels"), Type.bitstring(ID_2)),
        );
      });

      it("leaves a rule's clause the build sends as a marker", () => {
        defineCard({"update:status": [exact([{server: true}])]});

        assertSent(put(status("rejected")));
      });

      it("leaves a disjunction with an open alternative", () => {
        defineCard({
          "update:status": [
            exact([
              {
                or: [
                  [[newName("status"), "==", "approved"]],
                  [["title", "==", "t"]],
                ],
              },
            ]),
          ],
        });

        assertSent(put(status("rejected")));
      });

      it("leaves an integer past what a number holds exactly", () => {
        defineCard({
          "update:count": [
            exact([[newName("count"), "==", Number.MAX_SAFE_INTEGER + 1]]),
          ],
        });

        assertSent(
          put({count: Type.integer(BigInt(Number.MAX_SAFE_INTEGER) + 3n)}),
        );
      });

      it("leaves a float past what a number holds exactly", () => {
        defineCard({
          "update:rating": [
            exact([[newName("rating"), "!=", Number.MAX_SAFE_INTEGER + 1]]),
          ],
        });

        assertSent(put({rating: Type.float(Number.MAX_SAFE_INTEGER + 1)}));
      });

      it("leaves a value with a format, which the two regex engines can judge differently", () => {
        defineCard({"update:code": [newIs("code", "x")]});

        assertSent(put({code: Type.bitstring("ab")}));
      });

      it("leaves a refused field with a format, whose hint it can't be sure of", () => {
        defineCard({
          "update:code": [newIs("note", "x")],
          "update:note": [rule()],
        });

        assertSent(put({code: Type.bitstring("ab"), ...note("y")}));
      });

      it("leaves a date past what a JavaScript date holds", () => {
        defineCard({
          "update:held_at": [
            exact([[newName("held_at"), "==", "2026-01-01T00:00:00.000000Z"]]),
          ],
        });

        assertSent(put({held_at: datetimeInYear(280000)}));
      });

      it("leaves a datetime whose offset moves it past what a JavaScript date holds", () => {
        defineCard({
          "update:held_at": [
            exact([[newName("held_at"), ">=", "2026-01-01T00:00:00.000000Z"]]),
          ],
        });

        assertSent(put({held_at: datetimeInYear(2026, -10_000_000_000_000n)}));
      });

      it("doesn't refuse a field holding a far date, which a bound can't judge", () => {
        defineCard({
          "update:held_at": [newIs("note", "x")],
          "update:note": [rule()],
        });

        globalThis.Hologram.sync.model[CARD].constraints.held_at = {
          min: datetimeInYear(2000),
          optional: true,
        };

        Model.reset();

        const result = update(
          put({held_at: datetimeInYear(300000), ...note("y")}),
        );

        assert.deepStrictEqual(result.data[0], Type.atom("error"));
      });

      it("leaves a write with an open field beside a refused one", () => {
        defineCard({
          "update:note": [exact([{server: true}])],
          "update:status": [newIs("status", "approved")],
        });

        assertSent(put({...status("rejected"), ...note("y")}));
      });

      it("answers an invalid value with its violations when its rule is open", () => {
        defineCard({"update:status": [newIs("status", "approved")]});

        const result = update(put(status("bogus")));

        assert.deepStrictEqual(result.data[0], Type.atom("error"));
        assert.equal(Batches.current().writes.length, 0);
      });
    });
  });

  describe("update/3", () => {
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

    const changes = (values) =>
      Type.map(values.map(([name, value]) => [Type.atom(name), value]));

    it("writes the changes it was given", () => {
      assert.deepStrictEqual(
        updateById(
          task,
          Type.bitstring(ID_1),
          changes([["title", Type.bitstring("Ship it")]]),
        ),
        Type.atom("ok"),
      );

      assert.deepStrictEqual(Batches.current().writes, [
        {
          based_on: {title: 11},
          data: {title: "Ship it"},
          id: ID_1,
          op: "update",
          stamp: STAMP,
          type: TASK,
        },
      ]);
    });

    it("shows the change through the database", () => {
      updateById(
        task,
        Type.bitstring(ID_1),
        changes([["title", Type.bitstring("Ship it")]]),
      );

      assert.equal(LocalDatabase.getRow(TASK, ID_1).title, "Ship it");
    });

    describe("changes the server would refuse", () => {
      const invalid = (listed) =>
        `invalid changes for ${TASK} - only declared attributes and to-one relationships can be updated: ${listed}`;

      const pair = (name, value) => Type.tuple([name, value]);
      const nope = Type.atom("nope");

      const update = (given, id = ID_1) =>
        updateById(task, Type.bitstring(id), given);

      it("names a repeated unknown name once", () => {
        assertBoxedError(
          () =>
            update(
              Type.list([
                pair(nope, Type.integer(1)),
                pair(nope, Type.integer(2)),
              ]),
            ),
          "Hologram.MisuseError",
          invalid(":nope"),
        );
      });

      it("takes the last value of a repeated name", () => {
        const title = Type.atom("title");

        update(
          Type.list([
            pair(title, Type.bitstring("first")),
            pair(title, Type.bitstring("last")),
          ]),
        );

        assert.deepStrictEqual(Batches.current().writes[0].data, {
          title: "last",
        });
      });

      it("refuses an improper list as Map.new/1 does", () => {
        const improper = Type.improperList([
          pair(nope, Type.integer(1)),
          pair(Type.atom("other"), Type.integer(2)),
        ]);

        assertBoxedError(
          () => update(improper),
          "ArgumentError",
          "errors were found at the given arguments:\n\n  * 1st argument: not a proper list\n",
        );
      });

      it("refuses a list holding something other than a pair as Map.new/1 does", () => {
        assertBoxedError(
          () => update(Type.list([Type.integer(1)])),
          "ArgumentError",
          "argument error",
        );
      });

      it("reads a pair list whose key isn't an atom", () => {
        assertBoxedError(
          () => update(Type.list([pair(Type.bitstring("x"), Type.integer(1))])),
          "Hologram.MisuseError",
          invalid('"x"'),
        );
      });

      it("names every refused key in the order of its printed text", () => {
        assertBoxedError(
          () =>
            update(
              Type.map([
                [Type.map([]), Type.integer(1)],
                [nope, Type.integer(2)],
                [Type.bitstring("x"), Type.integer(3)],
                [Type.integer(7), Type.integer(4)],
                [Type.tuple([Type.atom("t")]), Type.integer(5)],
                [Type.list([Type.integer(1)]), Type.integer(6)],
              ]),
            ),
          "Hologram.MisuseError",
          invalid('"x", %{}, 7, :nope, [1], {:t}'),
        );
      });

      it("orders keys equal as numbers by their printed text", () => {
        assertBoxedError(
          () =>
            update(
              Type.map([
                [Type.float(1.0), Type.atom("a")],
                [Type.integer(1), Type.atom("b")],
              ]),
            ),
          "Hologram.MisuseError",
          invalid("1, 1.0"),
        );
      });

      it("orders keys whatever their values are", () => {
        const port = Type.port("nonode@nohost", [0, 11]);

        assertBoxedError(
          () =>
            update(
              Type.list([
                pair(Type.atom("a"), Type.integer(1)),
                pair(Type.integer(0), Type.integer(2)),
                pair(Type.integer(1), port),
                pair(Type.float(1.0), port),
              ]),
            ),
          "Hologram.MisuseError",
          invalid("0, 1, 1.0, :a"),
        );
      });

      it("refuses a bad value on a missing row with nobody signed in", () => {
        assertBoxedError(
          () => update(changes([["title", Type.integer(1)]]), ID_2),
          "Hologram.MisuseError",
          `cannot update ${TASK} - no entity with id "${ID_2}"`,
        );
      });

      it("refuses a bad value on a missing row for a signed-in user", () => {
        LocalDatabase.actorEntityId = ID_1;

        try {
          assertBoxedError(
            () => update(changes([["title", Type.integer(1)]]), ID_2),
            "Hologram.MisuseError",
            `cannot update ${TASK} - no entity with id "${ID_2}"`,
          );
        } finally {
          LocalDatabase.actorEntityId = null;
        }
      });

      it("reads an enumerable that isn't a list or a plain map", () => {
        const original = globalThis.Elixir_Enum;

        globalThis.Elixir_Enum = {
          "to_list/1": () =>
            Type.list([pair(Type.atom("title"), Type.bitstring("Ship it"))]),
        };

        try {
          update(Type.struct("MapSet", [[Type.atom("map"), Type.map([])]]));
        } finally {
          globalThis.Elixir_Enum = original;
        }

        assert.deepStrictEqual(Batches.current().writes[0].data, {
          title: "Ship it",
        });
      });

      it("answers no entity for a type the model doesn't carry", () => {
        assertBoxedError(
          () =>
            updateById(
              Type.alias("MyApp.Nothing"),
              Type.bitstring(ID_1),
              Type.map([[nope, Type.integer(1)]]),
            ),
          "Hologram.MisuseError",
          `cannot update MyApp.Nothing - no entity with id "${ID_1}"`,
        );
      });

      it("refuses an id that isn't a canonical UUID", () => {
        assertBoxedError(
          () =>
            update(
              changes([["title", Type.bitstring("Ship it")]]),
              "constructor",
            ),
          "Hologram.MisuseError",
          'invalid id "constructor" - entity ids are canonical lowercase 8-4-4-4-12 UUID strings',
        );
      });

      it("refuses a bitstring id that isn't a binary", () => {
        const id = Type.bitstring([1, 0, 1]);

        assertBoxedError(
          () =>
            updateById(
              task,
              id,
              changes([["title", Type.bitstring("Ship it")]]),
            ),
          "Hologram.MisuseError",
          `invalid id ${Interpreter.inspect(id)} - entity ids are canonical lowercase 8-4-4-4-12 UUID strings`,
        );
      });

      it("prints a map id with its keys sorted", () => {
        const id = Type.map([
          [Type.atom("zeta"), Type.integer(1)],
          [Type.atom("alpha"), Type.integer(2)],
        ]);

        assertBoxedError(
          () =>
            updateById(
              task,
              id,
              changes([["title", Type.bitstring("Ship it")]]),
            ),
          "Hologram.MisuseError",
          "invalid id %{alpha: 2, zeta: 1} - entity ids are canonical lowercase 8-4-4-4-12 UUID strings",
        );
      });

      it("refuses a nil id", () => {
        assertBoxedError(
          () =>
            updateById(
              task,
              Type.nil(),
              changes([["title", Type.bitstring("Ship it")]]),
            ),
          "Hologram.MisuseError",
          "invalid id nil - entity ids are canonical lowercase 8-4-4-4-12 UUID strings",
        );
      });

      it("judges the names before the id", () => {
        assertBoxedError(
          () => update(Type.map([[nope, Type.integer(1)]]), "constructor"),
          "Hologram.MisuseError",
          invalid(":nope"),
        );
      });

      it("reads no entry off the model object's prototype", () => {
        assertBoxedError(
          () =>
            updateById(
              Type.atom("constructor"),
              Type.bitstring(ID_1),
              Type.map([[nope, Type.integer(1)]]),
            ),
          "Hologram.MisuseError",
          `cannot update constructor - no entity with id "${ID_1}"`,
        );
      });

      it("judges the changes before looking up the row", () => {
        assertBoxedError(
          () => update(Type.map([[nope, Type.integer(1)]]), ID_2),
          "Hologram.MisuseError",
          invalid(":nope"),
        );
      });
    });

    it("names the given values in a refusal of update!/3 read as Map.new/1 reads them", () => {
      const original = globalThis.Elixir_Enum;

      globalThis.Elixir_Enum = {
        "to_list/1": () =>
          Type.list([Type.tuple([Type.atom("title"), Type.integer(1)])]),
      };

      try {
        assertBoxedError(
          () =>
            Elixir_Hologram_DB["update!/3"](
              task,
              Type.bitstring(ID_1),
              Type.struct("MapSet", [[Type.atom("map"), Type.map([])]]),
            ),
          "Hologram.WriteError",
          `cannot update ${TASK} "${ID_1}":\n  * attribute :title must be of type :string, got: 1`,
        );
      } finally {
        globalThis.Elixir_Enum = original;
      }
    });

    it("takes a keyword list as well as a map", () => {
      updateById(
        task,
        Type.bitstring(ID_1),
        Type.list([
          Type.tuple([Type.atom("title"), Type.bitstring("Ship it")]),
        ]),
      );

      assert.deepStrictEqual(Batches.current().writes[0].data, {
        title: "Ship it",
      });
    });

    it("answers a refusal from the declarations", () => {
      const result = updateById(
        task,
        Type.bitstring(ID_1),
        changes([["title", Type.nil()]]),
      );

      assert.deepStrictEqual(result.data[0], Type.atom("error"));
      assert.deepStrictEqual(Batches.current().writes, []);
    });

    it("raises for a row this client does not hold", () => {
      assertBoxedError(
        () =>
          updateById(
            task,
            Type.bitstring(ID_2),
            changes([["title", Type.bitstring("x")]]),
          ),
        "Hologram.MisuseError",
        `cannot update MyApp.Task - no entity with id "${ID_2}"`,
      );
    });

    it("raises when nothing is changed", () => {
      assertBoxedError(
        () => updateById(task, Type.bitstring(ID_1), changes([])),
        "Hologram.MisuseError",
        "invalid changes for MyApp.Task - at least one declared attribute or to-one relationship must be changed",
      );
    });

    it("raises on a change to a derived field", () => {
      assertBoxedError(
        () =>
          updateById(
            task,
            Type.bitstring(ID_1),
            changes([["tag_count", Type.integer(3)]]),
          ),
        "Hologram.MisuseError",
        "invalid changes for MyApp.Task - :tag_count is a derived field of MyApp.Task - it's computed from its definition, so it's read-only",
      );
    });

    // Every offending name at once, where the struct form refuses the first it meets - and a
    // system attribute is among them, because it is not a settable column.
    it("raises naming every field that cannot be updated", () => {
      assertBoxedError(
        () =>
          updateById(
            task,
            Type.bitstring(ID_1),
            changes([
              ["nope", Type.integer(1)],
              ["created_at", Type.nil()],
            ]),
          ),
        "Hologram.MisuseError",
        "invalid changes for MyApp.Task - only declared attributes and to-one relationships can be updated: :created_at, :nope",
      );
    });

    it("raises for a role grant", () => {
      assertBoxedError(
        () =>
          updateById(
            Type.alias(ROLE_GRANT),
            Type.bitstring(ID_1),
            changes([["role", Type.bitstring("editor")]]),
          ),
        "Hologram.MisuseError",
        "role grants are written only through grant_role/revoke_role",
      );
    });
  });

  describe("delete/1 and delete/2", () => {
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

      LocalDatabase.addFact(TASK, "tags", ID_1, "g1");
    });

    afterEach(() => {
      timers.restore();
    });

    const held = () => Model.box(TASK, LocalDatabase.getRow(TASK, ID_1));

    // A delete touches every column, so it says it was based on the whole map - the server keeps
    // it only if none of them moved since this client last saw the row.
    it("appends an entry based on the row's whole revision map", () => {
      assert.deepStrictEqual(deleteEntity(held()), Type.atom("ok"));

      assert.deepStrictEqual(Batches.current().writes, [
        {
          based_on: {done: 10, title: 11},
          id: ID_1,
          op: "delete",
          stamp: STAMP,
          type: TASK,
        },
      ]);
    });

    it("answers alike whether given a struct or a type and an id", () => {
      deleteEntity(held());

      const fromStruct = Batches.current().writes[0];

      Batches.discard();
      Batches.open("todos");
      deleteById(task, Type.bitstring(ID_1));

      assert.deepStrictEqual(Batches.current().writes[0], {
        ...fromStruct,
        stamp: Batches.current().writes[0].stamp,
      });
    });

    it("sends no claim", () => {
      deleteEntity(held());

      assert.notProperty(Batches.current().writes[0], "claim");
    });

    it("takes the row and its outgoing edges out of the database", () => {
      deleteById(task, Type.bitstring(ID_1));

      assert.isNull(LocalDatabase.getRow(TASK, ID_1));
      assert.deepStrictEqual(read(task), Type.list([]));

      assert.deepStrictEqual(
        LocalDatabase.getTargetIds(TASK, "tags", ID_1),
        new Set(),
      );
    });

    it("leaves the row the server sent untouched underneath", () => {
      deleteById(task, Type.bitstring(ID_1));

      assert.isNotNull(LocalDatabase.baseRow(TASK, ID_1));
    });

    it("puts the row back when the action's writes are discarded", () => {
      deleteById(task, Type.bitstring(ID_1));
      Batches.discard();

      assert.isNotNull(LocalDatabase.getRow(TASK, ID_1));
    });

    // D3, ruled 2026-08-29: the server answers :ok for a row that is not there, and that answer
    // does not carry - here "absent" also covers a row never synced and a row this user may not
    // see, so answering :ok would silently drop a delete of a row alive on the server.
    it("raises for a row this client does not hold", () => {
      assertBoxedError(
        () => deleteById(task, Type.bitstring(ID_2)),
        "Hologram.MisuseError",
        `cannot delete MyApp.Task - no entity with id "${ID_2}"`,
      );
    });

    it("raises for a struct whose row this client does not hold", () => {
      const absent = Model.box(TASK, {done: false, id: ID_2, title: "x"});

      assertBoxedError(
        () => deleteEntity(absent),
        "Hologram.MisuseError",
        `cannot delete MyApp.Task - no entity with id "${ID_2}"`,
      );
    });

    it("raises for a role grant", () => {
      assertBoxedError(
        () => deleteById(Type.alias(ROLE_GRANT), Type.bitstring(ID_1)),
        "Hologram.MisuseError",
        "role grants are written only through grant_role/revoke_role",
      );
    });

    it("raises when the value is not an entity struct", () => {
      assertBoxedError(
        () => deleteEntity(Type.bitstring("x")),
        "Hologram.MisuseError",
        'delete takes an entity struct, got: "x"',
      );
    });

    it("prints a query term passed where an entity struct goes", () => {
      const term = filter(task, predicates([["done", Type.boolean(true)]]));

      assertBoxedError(
        () => deleteEntity(term),
        "Hologram.MisuseError",
        `delete takes an entity struct, got: ${JSON.stringify(term)}`,
      );
    });

    it("raises when no action is open", () => {
      Batches.reset();

      assertBoxedError(
        () => deleteById(task, Type.bitstring(ID_1)),
        "Hologram.MisuseError",
        "delete was called outside an action - a client write happens inside an action, whose writes ship together when it returns",
      );
    });
  });

  describe("transaction/2 and rollback/1", () => {
    let timers;

    beforeEach(() => {
      timers = sinon.useFakeTimers(1_756_100_000_123);
      Batches.open("todos");
    });

    afterEach(() => {
      timers.restore();
    });

    // A zero-arity function as transpiled app code hands one over.
    const fun = (body) =>
      Type.anonymousFunction(
        0,
        [{params: (_context) => [], guards: [], body}],
        contextFixture(),
      );

    const noOpts = Type.list([]);

    const creating = (title) =>
      create(Model.box(TASK, {done: false, id: ID_1, title}));

    it("answers what the function returned", () => {
      assert.deepStrictEqual(
        transaction(
          fun(() => Type.atom("done")),
          noOpts,
        ),
        Type.tuple([Type.atom("ok"), Type.atom("done")]),
      );
    });

    it("keeps the writes made inside it", () => {
      transaction(
        fun(() => {
          creating("alpha");

          return Type.atom("done");
        }),
        noOpts,
      );

      assert.equal(Batches.current().writes.length, 1);
      assert.isNotNull(LocalDatabase.getRow(TASK, ID_1));
    });

    it("answers the reason a rollback named", () => {
      assert.deepStrictEqual(
        transaction(
          fun(() => rollback(Type.atom("locked"))),
          noOpts,
        ),
        Type.tuple([Type.atom("error"), Type.atom("locked")]),
      );
    });

    it("takes back the writes a rollback undoes", () => {
      transaction(
        fun(() => {
          creating("alpha");

          return rollback(Type.atom("locked"));
        }),
        noOpts,
      );

      assert.deepStrictEqual(Batches.current().writes, []);
      assert.isNull(LocalDatabase.getRow(TASK, ID_1));
    });

    // The action's own writes are not the transaction's to take back - only what it opened over.
    it("leaves the writes made before it alone", () => {
      creating("before");

      transaction(
        fun(() => {
          create(Model.box(TASK, {done: false, id: ID_2, title: "inside"}));

          return rollback(Type.atom("locked"));
        }),
        noOpts,
      );

      assert.equal(Batches.current().writes.length, 1);
      assert.isNotNull(LocalDatabase.getRow(TASK, ID_1));
      assert.isNull(LocalDatabase.getRow(TASK, ID_2));
    });

    it("takes back the writes a raise undoes, and re-raises", () => {
      assertBoxedError(
        () =>
          transaction(
            fun(() => {
              creating("alpha");

              return Interpreter.raiseArgumentError("boom");
            }),
            noOpts,
          ),
        "ArgumentError",
        "boom",
      );

      assert.deepStrictEqual(Batches.current().writes, []);
    });

    // A nested rollback stops at its own layer, and the enclosing transaction carries on.
    it("undoes what a nested transaction wrote and nothing more", () => {
      const result = transaction(
        fun(() => {
          creating("outer");

          const inner = transaction(
            fun(() => {
              create(Model.box(TASK, {done: false, id: ID_2, title: "inner"}));

              return rollback(Type.atom("nope"));
            }),
            noOpts,
          );

          return inner;
        }),
        noOpts,
      );

      assert.deepStrictEqual(
        result,
        Type.tuple([
          Type.atom("ok"),
          Type.tuple([Type.atom("error"), Type.atom("nope")]),
        ]),
      );

      assert.isNotNull(LocalDatabase.getRow(TASK, ID_1));
      assert.isNull(LocalDatabase.getRow(TASK, ID_2));
    });

    it("takes the arity-one spelling too", () => {
      assert.deepStrictEqual(
        Elixir_Hologram_DB["transaction/1"](fun(() => Type.atom("done"))),
        Type.tuple([Type.atom("ok"), Type.atom("done")]),
      );
    });

    it("raises for a rollback outside a transaction", () => {
      assertBoxedError(
        () => rollback(Type.atom("locked")),
        "Hologram.MisuseError",
        "cannot rollback - not inside a transaction",
      );
    });

    it("raises for a rollback after its transaction returned", () => {
      transaction(
        fun(() => Type.atom("done")),
        noOpts,
      );

      assertBoxedError(
        () => rollback(Type.atom("locked")),
        "Hologram.MisuseError",
        "cannot rollback - not inside a transaction",
      );
    });
  });

  describe("the bangs", () => {
    let timers;

    beforeEach(() => {
      timers = sinon.useFakeTimers(1_756_100_000_123);
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

    it("answers the written row when the write passes", () => {
      const result = createBang(
        Model.box(TASK, {done: false, id: ID_2, title: "alpha"}),
      );

      assert.deepStrictEqual(field(result, "title"), Type.bitstring("alpha"));
    });

    it("answers :ok when an update passes", () => {
      assert.deepStrictEqual(
        updateBang(
          putAttribute(held(), pairs([["title", Type.bitstring("x")]])),
        ),
        Type.atom("ok"),
      );
    });

    it("answers :ok when a delete passes", () => {
      assert.deepStrictEqual(
        deleteBang(task, Type.bitstring(ID_1)),
        Type.atom("ok"),
      );
    });

    it("raises naming the type and describing each violated declaration", () => {
      assertBoxedError(
        () => createBang(Model.box(TASK, {done: false, id: ID_2, title: null})),
        "Hologram.WriteError",
        "cannot create MyApp.Task:\n  * attribute :title is required",
      );
    });

    it("raises describing a bound the value broke, quoting the value", () => {
      LocalDatabase.putRow(ITEM, {
        id: ID_2,
        stock: 3,
        $revisions: {stock: 12},
      });

      const item = Model.box(ITEM, LocalDatabase.getRow(ITEM, ID_2));

      assertBoxedError(
        () =>
          updateBang(putAttribute(item, pairs([["stock", Type.integer(-1)]]))),
        "Hologram.WriteError",
        `cannot update MyApp.Item "${ID_2}":\n  * attribute :stock must be at least 0, got: -1`,
      );
    });

    it("raises for a type-indexed update, quoting the changes it was given", () => {
      assertBoxedError(
        () =>
          updateByIdBang(
            task,
            Type.bitstring(ID_1),
            Type.map([[Type.atom("title"), Type.nil()]]),
          ),
        "Hologram.WriteError",
        `cannot update MyApp.Task "${ID_1}":\n  * attribute :title is required`,
      );
    });

    it("carries the violations it raised on as its reason", () => {
      try {
        createBang(Model.box(TASK, {done: false, id: ID_2, title: null}));
        assert.fail("expected a raise");
      } catch (error) {
        const reason = field(error.struct, "reason");

        assert.deepStrictEqual(
          reason,
          Type.map([[Type.atom("title"), Type.list([Type.atom("required")])]]),
        );
      }
    });

    it("names the struct it raises", () => {
      try {
        createBang(Model.box(TASK, {done: false, id: ID_2, title: null}));
        assert.fail("expected a raise");
      } catch (error) {
        assert.equal(Model.structTypeName(error.struct), "Hologram.WriteError");
      }
    });

    // Two violations, so the ORDER is observable - the server sorts the boxed {field, reason}
    // pairs and this follows Elixir's own term order rather than a rule written twice.
    it("describes one line per violated declaration, in term order", () => {
      try {
        createBang(Model.box(TASK, {done: null, id: ID_2, title: null}));
        assert.fail("expected a raise");
      } catch (error) {
        const message = Bitstring.toText(field(error.struct, "message"));

        assert.equal(
          message,
          "cannot create MyApp.Task:\n" +
            "  * attribute :done is required\n" +
            "  * attribute :title is required",
        );
      }
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

    // The rows of a type sync never sends are never kept current, so reading them is refused.
    it("refuses a query reading a type sync doesn't send", () => {
      globalThis.Hologram.sync.syncedTypes = [];

      assertBoxedError(
        () => read(task),
        "Hologram.MisuseError",
        `DB.read can't answer the query: it reads ${TASK}, which browser code never names, so sync never sends its rows - name the entity type, or the relationship or derived field leading to it, as written in browser code, like include(project) or %Project{}`,
      );
    });

    // The browser never holds a server-only value, so a filter on one can't be answered from the
    // local rows. That refusal is told first, as a derived field's is, though the type doesn't sync
    // either.
    it("refuses a query filtering on a server-only attribute", () => {
      globalThis.Hologram.sync.syncedTypes = [];

      const doc = Type.alias(DOC);

      assertBoxedError(
        () =>
          read(filter(doc, predicates([["api_token", Type.bitstring("x")]]))),
        "Hologram.MisuseError",
        `DB.read can't answer the query: it filters or sorts on server_only attributes (${DOC} :api_token) - the client never holds those values, so it could not evaluate the reference locally. Drop the reference, or read the rows through the trusted backend API.`,
      );
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
  });

  describe("read/2", () => {
    it("refuses a type sync doesn't send, as read/1 does", () => {
      globalThis.Hologram.sync.syncedTypes = [];

      assertBoxedError(
        () => readById(task, Type.bitstring(ID_1)),
        "Hologram.MisuseError",
        `DB.read can't answer the query: it reads ${TASK}, which browser code never names, so sync never sends its rows - name the entity type, or the relationship or derived field leading to it, as written in browser code, like include(project) or %Project{}`,
      );
    });

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
      assertBoxedError(
        () => readById(task, Type.bitstring("nope")),
        "Hologram.MisuseError",
        'invalid id "nope" - entity ids are canonical lowercase 8-4-4-4-12 UUID strings',
      );

      assertBoxedError(
        () => readById(task, Type.bitstring(ID_1.toUpperCase())),
        "Hologram.MisuseError",
        `invalid id "${ID_1.toUpperCase()}" - entity ids are canonical lowercase 8-4-4-4-12 UUID strings`,
      );
    });

    it("raises when the first argument is not an entity type module", () => {
      const term = filter(task, predicates([["done", Type.boolean(true)]]));

      assertBoxedError(
        () => readById(term, Type.bitstring(ID_1)),
        "Hologram.MisuseError",
        `${JSON.stringify(term)} is not an entity type module - a by-id read takes the entity type, a query term is read with read/1`,
      );
    });

    // A module name this build carries no entity for reaches the second half of the check, where
    // a query term is refused by the first.
    it("raises when the module names no entity type this build carries", () => {
      assertBoxedError(
        () => readById(Type.alias("MyApp.Nope"), Type.bitstring(ID_1)),
        "Hologram.MisuseError",
        "MyApp.Nope is not an entity type module - a by-id read takes the entity type, a query term is read with read/1",
      );
    });
  });
});
