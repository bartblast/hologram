"use strict";

import {assert, defineRuntimeGlobals, sinon} from "./support/helpers.mjs";

import Batch from "../../assets/js/batch.mjs";
import Batches from "../../assets/js/batches.mjs";
import DataLayer from "../../assets/js/data_layer.mjs";
import Deltas from "../../assets/js/deltas.mjs";
import Durability from "../../assets/js/durability.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import ManuallyPortedElixirHologramAuth from "../../assets/js/elixir/hologram/auth.mjs";
import ManuallyPortedElixirHologramDB from "../../assets/js/elixir/hologram/db.mjs";
import ManuallyPortedElixirHologramEntity from "../../assets/js/elixir/hologram/entity.mjs";
import ManuallyPortedElixirHologramJob from "../../assets/js/elixir/hologram/job.mjs";
import ManuallyPortedElixirHologramQueryStage from "../../assets/js/elixir/hologram/query/stage.mjs";
import Model from "../../assets/js/model.mjs";
import Overlay from "../../assets/js/overlay.mjs";
import ReloadNotice from "../../assets/js/reload_notice.mjs";
import Replica from "../../assets/js/replica.mjs";
import SyncStream from "../../assets/js/sync_stream.mjs";
import Tabs from "../../assets/js/tabs.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

describe("DataLayer", () => {
  afterEach(() => {
    sinon.restore();
  });

  describe("answerDerivedQuery()", () => {
    const TASK = "MyApp.Task";

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [TASK]: {
            attributes: {done: "boolean", id: "uuid", title: "string"},
            relationships: {},
            serverOnly: [],
          },
        },
      };

      Model.reset();
      LocalDatabase.reset();

      LocalDatabase.putRow(TASK, {
        done: false,
        id: "t1",
        title: "Buy milk",
        title$sort: "buy milk",
      });
      LocalDatabase.putRow(TASK, {
        done: true,
        id: "t2",
        title: "Call Ann",
        title$sort: "call ann",
      });
    });

    afterEach(() => {
      LocalDatabase.reset();
      delete globalThis.Hologram.sync;
    });

    it("answers a count from the local database", () => {
      const term = DataLayer.normalizeQuery(
        ManuallyPortedElixirHologramQueryStage["count/1"](Type.alias(TASK)),
      );

      assert.deepStrictEqual(
        DataLayer.answerDerivedQuery(
          "MyApp.Tasks",
          Type.atom("total"),
          [],
          term,
        ),
        Type.integer(2),
      );
    });

    const MODULE_2 = "Hologram.Test.Fixtures.Entity.Module2";

    // The same keys as the server's (see the collect_count/4 tests in
    // test/elixir/hologram/sync/carry_test.exs).
    const carriedFor = (arg, key) => {
      globalThis.Hologram.sync.model[MODULE_2] = {
        attributes: {id: "uuid"},
        relationships: {},
        serverOnly: [],
      };

      const term = DataLayer.normalizeQuery(
        ManuallyPortedElixirHologramQueryStage["count/1"](Type.alias(TASK)),
      );

      LocalDatabase.syncCounts = {[`${MODULE_2}/total/${key}`]: 42};

      return DataLayer.answerDerivedQuery(
        MODULE_2,
        Type.atom("total"),
        [arg],
        term,
      );
    };

    it("spells an entity row in the key by its type and id", () => {
      const row = Type.struct(MODULE_2, [
        [Type.atom("__meta__"), Model.emptyMetadata()],
        [Type.atom("a"), Type.boolean(true)],
        [
          Type.atom("id"),
          Type.bitstring("01a1cbe6-0000-7000-8000-000000000001"),
        ],
      ]);

      assert.deepStrictEqual(
        carriedFor(
          Type.list([row]),
          "[Hologram.Test.Fixtures.Entity.Module2#01a1cbe6-0000-7000-8000-000000000001]",
        ),
        Type.integer(42),
      );
    });

    it("spells a row of a type the model doesn't bake by its type and id", () => {
      const row = Type.struct("MyApp.Unbaked", [
        [Type.atom("__meta__"), Model.emptyMetadata()],
        [Type.atom("id"), Type.bitstring("x")],
      ]);

      assert.deepStrictEqual(
        carriedFor(row, "MyApp.Unbaked#x"),
        Type.integer(42),
      );
    });

    it("spells an improper list in the key with its tail after a bar", () => {
      assert.deepStrictEqual(
        carriedFor(
          Type.improperList([Type.integer(1), Type.integer(2)]),
          "[1 | 2]",
        ),
        Type.integer(42),
      );
    });

    it("spells a float in the key by its bits", () => {
      assert.deepStrictEqual(
        carriedFor(Type.float(1.0e20), "float:4415af1d78b58c40"),
        Type.integer(42),
      );
    });

    it("sorts a map's entries in the key in code point order", () => {
      const map = Type.map([
        [Type.bitstring("😀"), Type.integer(2)],
        [Type.bitstring("！"), Type.integer(1)],
      ]);

      assert.deepStrictEqual(
        carriedFor(map, '%{"！" => 1, "😀" => 2}'),
        Type.integer(42),
      );
    });

    it("spells a tuple in the key by its items", () => {
      assert.deepStrictEqual(
        carriedFor(
          Type.tuple([Type.integer(1), Type.bitstring("a")]),
          '{1, "a"}',
        ),
        Type.integer(42),
      );
    });

    it("spells a struct in the key by its fields, sorted by name", () => {
      const date = Type.struct("Date", [
        [Type.atom("year"), Type.integer(2026)],
        [Type.atom("month"), Type.integer(1)],
        [Type.atom("day"), Type.integer(2)],
        [Type.atom("calendar"), Type.alias("Calendar.ISO")],
      ]);

      assert.deepStrictEqual(
        carriedFor(
          date,
          "%Date{calendar: Calendar.ISO, day: 2, month: 1, year: 2026}",
        ),
        Type.integer(42),
      );
    });

    it("spells a map in the key by its entries, sorted by key", () => {
      const map = Type.map([
        [Type.atom("b"), Type.integer(1)],
        [Type.atom("a"), Type.integer(2)],
      ]);

      assert.deepStrictEqual(
        carriedFor(map, "%{:a => 2, :b => 1}"),
        Type.integer(42),
      );
    });

    // Two structs of one row are two keys that spell alike.
    it("spells a map whose keys spell alike in the key by its entries, sorted by value", () => {
      const row = (a) =>
        Type.struct(MODULE_2, [
          [Type.atom("__meta__"), Model.emptyMetadata()],
          [Type.atom("a"), Type.boolean(a)],
          [Type.atom("id"), Type.bitstring("x")],
        ]);

      const map = Type.map([
        [row(true), Type.integer(2)],
        [row(false), Type.integer(1)],
      ]);

      assert.deepStrictEqual(
        carriedFor(map, `%{${MODULE_2}#x => 1, ${MODULE_2}#x => 2}`),
        Type.integer(42),
      );
    });

    it("answers a count with the count the page carried under the field's name and arguments", () => {
      const term = DataLayer.normalizeQuery(
        ManuallyPortedElixirHologramQueryStage["count/1"](Type.alias(TASK)),
      );

      LocalDatabase.syncCounts = {"MyApp.Tasks/total/5": 42};

      assert.deepStrictEqual(
        DataLayer.answerDerivedQuery(
          "MyApp.Tasks",
          Type.atom("total"),
          [Type.integer(5)],
          term,
        ),
        Type.integer(42),
      );
    });

    const count = ManuallyPortedElixirHologramQueryStage["count/1"];
    const filter = ManuallyPortedElixirHologramQueryStage["filter/2"];
    const sort = ManuallyPortedElixirHologramQueryStage["sort/2"];

    const notDoneCount = () =>
      DataLayer.normalizeQuery(
        count(
          filter(
            Type.alias(TASK),
            Type.list([Type.tuple([Type.atom("done"), Type.boolean(false)])]),
          ),
        ),
      );

    const sortedByTitle = () =>
      DataLayer.normalizeQuery(sort(Type.alias(TASK), Type.atom("title")));

    // The struct type and the title of each boxed task, in the order the result holds them.
    const boxedTasks = (result) =>
      result.data.map((task) => [
        task.data[Type.encodeMapKey(Type.atom("__struct__"))][1],
        task.data[Type.encodeMapKey(Type.atom("title"))][1].text,
      ]);

    const allTasks = () => [
      [Type.alias(TASK), "Buy milk"],
      [Type.alias(TASK), "Call Ann"],
    ];

    it("answers rows from the local database, boxed for the template", () => {
      const result = DataLayer.answerDerivedQuery(
        "MyApp.Listing",
        Type.atom("tasks"),
        [],
        sortedByTitle(),
      );

      assert.deepStrictEqual(boxedTasks(result), allTasks());
    });

    it("counts locally once the whole pot is complete", () => {
      LocalDatabase.syncCounts = {"MyApp.Complete/count/false": 42};
      LocalDatabase.markAllSynced();

      const result = DataLayer.answerDerivedQuery(
        "MyApp.Complete",
        Type.atom("count"),
        [Type.boolean(false)],
        notDoneCount(),
      );

      assert.deepStrictEqual(result, Type.integer(1));
    });

    const countReading = (module, types) => {
      globalThis.Hologram.sync.countTypes = {[module]: {count: types}};
    };

    // Whichever page the component is on, and whether or not the stream connected on it: a type's
    // marker is a claim about the rows the client holds.
    it("counts locally once every type the count reads is complete", () => {
      countReading("MyApp.NavigatedTo", [TASK, "MyApp.Project"]);
      LocalDatabase.syncCounts = {"MyApp.NavigatedTo/count/false": 42};
      LocalDatabase.markTypesSynced([TASK, "MyApp.Project"]);

      const result = DataLayer.answerDerivedQuery(
        "MyApp.NavigatedTo",
        Type.atom("count"),
        [Type.boolean(false)],
        notDoneCount(),
      );

      assert.deepStrictEqual(result, Type.integer(1));
    });

    it("keeps carrying while a type the count reads is not complete", () => {
      countReading("MyApp.NavigatedTo", [TASK, "MyApp.Project"]);
      LocalDatabase.syncCounts = {"MyApp.NavigatedTo/count/false": 42};
      LocalDatabase.markTypesSynced([TASK]);

      const result = DataLayer.answerDerivedQuery(
        "MyApp.NavigatedTo",
        Type.atom("count"),
        [Type.boolean(false)],
        notDoneCount(),
      );

      assert.deepStrictEqual(result, Type.integer(42));
    });

    // A tab that took over the stream greets with the page it is on, which may not be the page the
    // completeness it holds was told for (#1582). A type's marker is the same claim on every page,
    // so the count waits for the types it reads, whatever page the stream was greeted with.
    it("keeps carrying on a page reached by a tab that took over while a type the count reads is not complete", () => {
      countReading("MyApp.TakenOverPage", ["MyApp.Project"]);
      LocalDatabase.syncCounts = {"MyApp.TakenOverPage/count/false": 42};
      LocalDatabase.markTypesSynced([TASK]);

      const result = DataLayer.answerDerivedQuery(
        "MyApp.TakenOverPage",
        Type.atom("count"),
        [Type.boolean(false)],
        notDoneCount(),
      );

      assert.deepStrictEqual(result, Type.integer(42));
    });

    // A field the build listed no types for can only count on the whole pot.
    it("keeps carrying until everything is complete for a count with no types listed", () => {
      LocalDatabase.syncCounts = {"MyApp.Unlisted/count/false": 42};
      LocalDatabase.markTypesSynced([TASK]);

      const result = DataLayer.answerDerivedQuery(
        "MyApp.Unlisted",
        Type.atom("count"),
        [Type.boolean(false)],
        notDoneCount(),
      );

      assert.deepStrictEqual(result, Type.integer(42));
    });

    // Two instances of one component answer two counts, and the arguments their functions were
    // called with are what tell them apart.
    it("reads the count of the arguments the function was called with", () => {
      LocalDatabase.syncCounts = {
        "MyApp.TwoInstances/count/false": 42,
        "MyApp.TwoInstances/count/true": 7,
      };

      const result = DataLayer.answerDerivedQuery(
        "MyApp.TwoInstances",
        Type.atom("count"),
        [Type.boolean(true)],
        notDoneCount(),
      );

      assert.deepStrictEqual(result, Type.integer(7));
    });

    // Two arguments are two values, not their concatenation: 1 and 23 must not read the key
    // 12 and 3 wrote.
    it("separates the arguments a function reading two fields was called with", () => {
      LocalDatabase.syncCounts = {
        "MyApp.TwoArgs/count/1,23": 42,
        "MyApp.TwoArgs/count/123": 7,
      };

      const result = DataLayer.answerDerivedQuery(
        "MyApp.TwoArgs",
        Type.atom("count"),
        [Type.integer(1), Type.integer(23)],
        DataLayer.normalizeQuery(count(Type.alias(TASK))),
      );

      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("leaves a query that does not count alone", () => {
      LocalDatabase.syncCounts = {"MyApp.NotCounting/tasks/": 42};

      const result = DataLayer.answerDerivedQuery(
        "MyApp.NotCounting",
        Type.atom("tasks"),
        [],
        sortedByTitle(),
      );

      assert.deepStrictEqual(boxedTasks(result), allTasks());
    });
  });

  describe("boot()", () => {
    const identity = (readActorUserId = () => "u1") => ({
      readActorUserId: readActorUserId,
      replica: {id: "r1", token: "SFMyNTY.minted"},
    });

    let joining, offering, opening, originalMode;

    beforeEach(() => {
      originalMode = Durability.mode;

      offering = sinon.stub(Replica, "offer");
      opening = sinon.stub(Durability, "open").resolves();
      joining = sinon.stub(Tabs, "join").resolves();

      sinon.stub(Durability, "databaseName").returns("hologram.1.a3f9c2");
    });

    afterEach(() => {
      Durability.mode = originalMode;

      delete globalThis.Hologram.durability;
      delete globalThis.Hologram.writes;
    });

    it("offers the page's replica pair before the store is read", async () => {
      Durability.mode = "memory";

      await DataLayer.boot(identity());

      sinon.assert.calledOnceWithExactly(offering, {
        id: "r1",
        token: "SFMyNTY.minted",
      });

      assert.isTrue(offering.calledBefore(opening));
    });

    it("joins the group named for the database and the acting user", async () => {
      Durability.mode = "indexeddb";

      await DataLayer.boot(identity());

      sinon.assert.calledOnceWithExactly(joining, "hologram.1.a3f9c2.u1", {});
      assert.isTrue(joining.calledAfter(opening));
    });

    // The join comes before the mount, so boot is not done while the join is still pending.
    it("resolves only once the group is joined", async () => {
      let finishJoin;

      joining.returns(new Promise((resolve) => (finishJoin = resolve)));
      Durability.mode = "indexeddb";

      let booted = false;
      const booting = DataLayer.boot(identity()).then(() => (booted = true));

      await new Promise((resolve) => setImmediate(resolve));
      assert.isFalse(booted);

      finishJoin();
      await booting;

      assert.isTrue(booted);
    });

    it("joins as anonymous when the page mounts under no user", async () => {
      Durability.mode = "indexeddb";

      await DataLayer.boot(identity(() => null));

      sinon.assert.calledOnceWithExactly(
        joining,
        "hologram.1.a3f9c2.anonymous",
        {},
      );
    });

    // The tabs of a browser that cannot store share nothing, so each is a replica of its own - and
    // the actor, read only to name the group, is not read at all.
    it("joins no group when the store is in memory", async () => {
      const reading = sinon.spy(() => "u1");

      Durability.mode = "memory";

      await DataLayer.boot(identity(reading));

      sinon.assert.notCalled(joining);
      sinon.assert.notCalled(reading);
    });

    describe("the read-only windows", () => {
      let originals;

      beforeEach(() => {
        originals = {
          inFlight: Durability.inFlight,
          leader: Tabs.leader,
          name: Tabs.name,
          persisted: Durability.persisted,
          storedBatches: Durability.storedBatches,
        };

        Durability.inFlight = 2;
        Durability.persisted = true;
        Durability.storedBatches = 3;
        Replica.adopt({id: "r-held", token: "SFMyNTY.held"});
        SyncStream.syncCursor = "Nzc4LjA";
        Tabs.leader = false;
        Tabs.name = "hologram.1.a3f9c2.u1";
      });

      afterEach(() => {
        Durability.inFlight = originals.inFlight;
        Durability.persisted = originals.persisted;
        Durability.storedBatches = originals.storedBatches;
        Replica.reset();
        SyncStream.syncCursor = null;
        Tabs.leader = originals.leader;
        Tabs.name = originals.name;
      });

      for (const mode of ["indexeddb", "memory"]) {
        it(`opens them onto the write queue and the store, in ${mode} mode`, async () => {
          Durability.mode = mode;

          await DataLayer.boot(identity());

          assert.deepStrictEqual(globalThis.Hologram.writes, {
            oldestPendingSeq: Batches.oldestPendingSeq,
            pendingCount: Batches.pendingCount,
            rejected: Batches.rejectedSummaries,
          });

          const durability = globalThis.Hologram.durability;

          assert.deepStrictEqual(
            Object.fromEntries(
              Object.entries(durability).map(([key, read]) => [key, read()]),
            ),
            {
              cursor: "Nzc4LjA",
              group: "hologram.1.a3f9c2.u1",
              leader: false,
              mode: mode,
              pendingWrites: 2,
              persisted: true,
              replicaId: "r-held",
              storedBatches: 3,
            },
          );
        });
      }
    });
  });

  describe("buildStreamGreeting()", () => {
    it("answers the greeting the sync stream builds", () => {
      const pageModule = Type.atom("Elixir.MyApp.BoardPage");
      const greeting = {page: "MyApp.BoardPage"};

      const building = sinon
        .stub(SyncStream, "buildGreeting")
        .returns(greeting);

      assert.strictEqual(DataLayer.buildStreamGreeting(pageModule), greeting);
      sinon.assert.calledOnceWithExactly(building, pageModule);
    });
  });

  describe("carryAcrossSuspension()", () => {
    it("hands the batch over to the promise the action awaits", () => {
      const promise = Promise.resolve();
      const carried = Promise.resolve();

      const carrying = sinon
        .stub(Batches, "carryAcrossSuspension")
        .returns(carried);

      assert.strictEqual(DataLayer.carryAcrossSuspension(promise), carried);
      sinon.assert.calledOnceWithExactly(carrying, promise);
    });
  });

  describe("closeBatch()", () => {
    it("seals the action's batch", () => {
      const closing = sinon.stub(Batches, "close");

      DataLayer.closeBatch();

      sinon.assert.calledOnceWithExactly(closing);
    });
  });

  describe("defineManuallyPortedFunctions()", () => {
    // Global module proxies, so each is put back the way it was found: a proxy left behind here
    // would answer for its module in every file that runs after this one.
    const MODULES = [
      "Elixir_Hologram_Auth",
      "Elixir_Hologram_DB",
      "Elixir_Hologram_Entity",
      "Elixir_Hologram_Job",
      "Elixir_Hologram_Query_Stage",
    ];

    let originals;

    beforeEach(() => {
      originals = Object.fromEntries(
        MODULES.map((name) => [name, globalThis[name]]),
      );

      MODULES.forEach((name) => delete globalThis[name]);
    });

    afterEach(() => {
      MODULES.forEach((name) => {
        if (originals[name] === undefined) {
          delete globalThis[name];
        } else {
          globalThis[name] = originals[name];
        }
      });
    });

    it("defines the hand-written Auth, DB, Entity, Job and Query.Stage functions as public functions of their modules", () => {
      DataLayer.defineManuallyPortedFunctions();

      assert.deepStrictEqual(
        globalThis.Elixir_Hologram_Auth.__exports__,
        new Set([
          "can?/3",
          "grant_role/2",
          "grant_role/3",
          "has_role?/2",
          "has_role?/3",
          "revoke_role/2",
          "revoke_role/3",
        ]),
      );

      assert.deepStrictEqual(
        globalThis.Elixir_Hologram_DB.__exports__,
        new Set([
          "create!/1",
          "create/1",
          "delete!/1",
          "delete!/2",
          "delete/1",
          "delete/2",
          "read/1",
          "read/2",
          "rollback/1",
          "transaction/1",
          "transaction/2",
          "update!/1",
          "update!/3",
          "update/1",
          "update/3",
        ]),
      );

      assert.deepStrictEqual(
        globalThis.Elixir_Hologram_Entity.__exports__,
        new Set([
          "generate_id/0",
          "new/1",
          "new/2",
          "validate/1",
          "validate/2",
        ]),
      );

      assert.deepStrictEqual(
        globalThis.Elixir_Hologram_Job.__exports__,
        new Set([
          "create!/1",
          "create!/2",
          "create!/3",
          "create/1",
          "create/2",
          "create/3",
          "framework_attribute_names/0",
        ]),
      );

      assert.deepStrictEqual(
        globalThis.Elixir_Hologram_Query_Stage.__exports__,
        new Set([
          "add_relationship/3",
          "count/1",
          "decrement/3",
          "delete_relationship/3",
          "filter/2",
          "include/2",
          "increment/3",
          "normalize/1",
          "one/1",
          "put_attribute/2",
          "put_attribute/3",
          "skip/2",
          "sort/2",
          "take/2",
          "trust/1",
        ]),
      );
    });

    // Every port function is stubbed before the definitions read it, so each definition is seen
    // reaching its own port function with the arguments it was called with - a definition pointing
    // at another port function, or at a key the port does not have, answers something else.
    it("defines each function as its own hand-written version", () => {
      const ports = {
        Elixir_Hologram_Auth: ManuallyPortedElixirHologramAuth,
        Elixir_Hologram_DB: ManuallyPortedElixirHologramDB,
        Elixir_Hologram_Entity: ManuallyPortedElixirHologramEntity,
        Elixir_Hologram_Job: ManuallyPortedElixirHologramJob,
        Elixir_Hologram_Query_Stage: ManuallyPortedElixirHologramQueryStage,
      };

      for (const [moduleName, port] of Object.entries(ports)) {
        for (const key of Object.keys(port)) {
          sinon.stub(port, key).callsFake((...args) => [moduleName, key, args]);
        }
      }

      DataLayer.defineManuallyPortedFunctions();

      for (const moduleName of MODULES) {
        for (const key of globalThis[moduleName].__exports__) {
          const arg = Type.atom("arg");

          assert.deepStrictEqual(globalThis[moduleName][key](arg), [
            moduleName,
            key,
            [arg],
          ]);
        }
      }
    });
  });

  describe("discardBatch()", () => {
    it("drops the action's batch", () => {
      const discarding = sinon.stub(Batches, "discard");

      DataLayer.discardBatch();

      sinon.assert.calledOnceWithExactly(discarding);
    });
  });

  describe("flush()", () => {
    it("wakes the sender", () => {
      const flushing = sinon.stub(Batches, "flush");

      DataLayer.flush();

      sinon.assert.calledOnceWithExactly(flushing);
    });
  });

  describe("ingestMountData()", () => {
    let applying;

    beforeEach(() => {
      applying = sinon.stub(Deltas, "apply");

      LocalDatabase.actorUserId = null;
      LocalDatabase.syncCounts = {};
    });

    afterEach(() => {
      LocalDatabase.actorUserId = null;
      LocalDatabase.syncCounts = {};
    });

    it("files the rows the page carried, and the counts beside them", () => {
      const rows = {put_entity: {"MyApp.Task": [{id: "t1"}]}};

      DataLayer.ingestMountData({
        actorUserId: "u1",
        syncCounts: {"MyApp.Counting/count/": 3},
        syncRows: rows,
      });

      sinon.assert.calledOnceWithExactly(applying, rows, {insertOnly: true});

      assert.equal(LocalDatabase.actorUserId, "u1");

      assert.deepStrictEqual(LocalDatabase.syncCounts, {
        "MyApp.Counting/count/": 3,
      });
    });

    it("takes counts the page did not carry as none", () => {
      LocalDatabase.syncCounts = {"MyApp.Stale/count/": 9};

      DataLayer.ingestMountData({actorUserId: null, syncRows: {}});

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
    });

    it("leaves the database as it was for mount data carrying no rows", () => {
      LocalDatabase.syncCounts = {"MyApp.Held/count/": 9};

      DataLayer.ingestMountData({actorUserId: "u1", syncCounts: {}});

      sinon.assert.notCalled(applying);

      assert.isNull(LocalDatabase.actorUserId);
      assert.deepStrictEqual(LocalDatabase.syncCounts, {
        "MyApp.Held/count/": 9,
      });
    });
  });

  describe("listenToStream()", () => {
    it("hands the stream to the sync stream to listen on", () => {
      const eventSource = {addEventListener: () => {}};
      const listening = sinon.stub(SyncStream, "listen");

      DataLayer.listenToStream(eventSource);

      sinon.assert.calledOnceWithExactly(listening, eventSource);
    });
  });

  describe("markRendered()", () => {
    it("marks the rows as the ones the last render saw", () => {
      SyncStream.rowsChangedSinceRender = true;

      DataLayer.markRendered();

      assert.isFalse(DataLayer.rowsChangedSinceRender());
    });
  });

  describe("normalizeQuery()", () => {
    it("normalizes a query as the server does before running it", () => {
      globalThis.Hologram.sync = {
        model: {
          "MyApp.Task": {
            attributes: {id: "uuid"},
            relationships: {},
            serverOnly: [],
          },
        },
      };

      Model.reset();

      assert.deepStrictEqual(
        DataLayer.normalizeQuery(Type.alias("MyApp.Task")),
        ManuallyPortedElixirHologramQueryStage["normalize/1"](
          Type.alias("MyApp.Task"),
        ),
      );
    });
  });

  describe("openBatch()", () => {
    it("opens the action's batch for its target", () => {
      const opening = sinon.stub(Batches, "open");

      DataLayer.openBatch("my_component");

      sinon.assert.calledOnceWithExactly(opening, "my_component");
    });
  });

  describe("rendered()", () => {
    afterEach(() => {
      SyncStream.stopReason = null;
    });

    it("puts the notice up in a tab the server stopped", () => {
      const updating = sinon.stub(ReloadNotice, "update");

      SyncStream.stopReason = "model_hash";

      DataLayer.rendered();

      sinon.assert.calledOnceWithExactly(updating, true);
    });

    it("leaves the notice down in a tab the server serves", () => {
      const updating = sinon.stub(ReloadNotice, "update");

      DataLayer.rendered();

      sinon.assert.calledOnceWithExactly(updating, false);
    });
  });

  describe("restore()", () => {
    let adopting, flushing, posting, readying, resuming;

    beforeEach(() => {
      adopting = sinon.stub(Batches, "adopt");
      flushing = sinon.stub(Batches, "flush");
      resuming = sinon.stub(Batches, "resumeFrom");
      posting = sinon.stub(Tabs, "post");
      readying = sinon.stub(Tabs, "ready");
    });

    afterEach(() => {
      SyncStream.syncCursor = null;
      Tabs.leader = true;
    });

    it("takes up what a previous page load left", () => {
      const batch = {seq: 4, writes: []};

      const restoring = sinon.stub(Durability, "restore").returns({
        batches: [batch],
        cursor: "Nzc4LjA",
        seq: 5,
      });

      // Not the default, so the hook is seen passing the tab's own answer rather than a literal.
      Tabs.leader = false;

      DataLayer.restore();

      sinon.assert.calledOnceWithExactly(restoring, false);
      sinon.assert.calledOnceWithExactly(resuming, 5);
      sinon.assert.calledOnceWithExactly(adopting, [batch]);
      sinon.assert.calledOnceWithExactly(posting, {kind: "joined"});
      sinon.assert.calledOnce(readying);

      assert.equal(SyncStream.syncCursor, "Nzc4LjA");

      // The counter first, then the batches it counts on from; the tab ready before it asks the
      // group for what the store could not tell it.
      assert.isTrue(resuming.calledBefore(adopting));
      assert.isTrue(readying.calledBefore(posting));

      // The stream can have opened, and flushed an empty queue, before these batches were taken
      // up - so the sender is woken after them.
      assert.isTrue(flushing.calledAfter(adopting));
    });

    it("does nothing on a visit after the first", () => {
      sinon.stub(Durability, "restore").returns(null);

      DataLayer.restore();

      sinon.assert.notCalled(resuming);
      sinon.assert.notCalled(adopting);
      sinon.assert.notCalled(readying);
      sinon.assert.notCalled(posting);
      sinon.assert.notCalled(flushing);

      assert.isNull(SyncStream.syncCursor);
    });
  });

  describe("rowsChangedSinceRender()", () => {
    afterEach(() => {
      SyncStream.rowsChangedSinceRender = false;
    });

    it("answers whether rows changed since the last render", () => {
      SyncStream.rowsChangedSinceRender = true;

      assert.isTrue(DataLayer.rowsChangedSinceRender());
    });
  });

  describe("saved()", () => {
    it("waits for what this tab sealed to be written down", async () => {
      const recording = sinon.stub(Batches, "recorded").resolves([]);

      await DataLayer.saved();

      sinon.assert.calledOnce(recording);
    });

    // A store write that never answers would otherwise leave a link doing nothing.
    it("stops waiting after three seconds", async () => {
      const clock = sinon.useFakeTimers();

      sinon.stub(Batches, "recorded").returns(new Promise(() => {}));

      let settled = false;

      DataLayer.saved().then(() => {
        settled = true;
      });

      await clock.tickAsync(2999);

      assert.isFalse(settled);

      await clock.tickAsync(1);

      assert.isTrue(settled);
    });
  });

  describe("sessionUser()", () => {
    const USER = "MyApp.User";

    const field = (boxed, name) =>
      boxed.data[Type.encodeMapKey(Type.atom(name))][1];

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [USER]: {
            attributes: {email: "string", id: "uuid", password_hash: "string"},
            relationships: {},
            serverOnly: ["password_hash"],
          },
        },
        userEntity: USER,
      };

      Model.reset();
      LocalDatabase.reset();
      LocalDatabase.actorUserId = "u1";

      LocalDatabase.putRow(USER, {
        email: "ann@example.com",
        email$sort: "ann@example.com",
        id: "u1",
      });

      LocalDatabase.putRow(USER, {
        email: "bob@example.com",
        email$sort: "bob@example.com",
        id: "u2",
      });
    });

    afterEach(() => {
      LocalDatabase.reset();
      LocalDatabase.actorUserId = null;
      Overlay.reset();
      delete globalThis.Hologram.sync;
    });

    it("answers the acting user's row", () => {
      const user = DataLayer.sessionUser();

      assert.deepStrictEqual(field(user, "id"), Type.bitstring("u1"));

      assert.deepStrictEqual(
        field(user, "email"),
        Type.bitstring("ann@example.com"),
      );
    });

    // What the server hands over for it in the context too.
    it("answers an attribute the client may not have as the sentinel naming it", () => {
      assert.deepStrictEqual(
        field(DataLayer.sessionUser(), "password_hash"),
        Type.map([
          [Type.atom("__struct__"), Type.alias("Hologram.Entity.ServerOnly")],
          [Type.atom("attribute"), Type.atom("password_hash")],
        ]),
      );
    });

    it("answers the row as it stands now", () => {
      LocalDatabase.putRow(USER, {
        email: "ann@example.org",
        email$sort: "ann@example.org",
        id: "u1",
      });

      assert.deepStrictEqual(
        field(DataLayer.sessionUser(), "email"),
        Type.bitstring("ann@example.org"),
      );
    });

    // The server confirms a write within moments and syncs the row back, so a feature test can't
    // tell the pending write from the synced row.
    it("answers the row with this tab's pending writes applied", () => {
      const batch = new Batch("users");

      batch.append({
        data: {email: "ann@example.org"},
        id: "u1",
        op: "update",
        stamp: 1,
        type: USER,
      });

      Overlay.push(batch);

      assert.deepStrictEqual(
        field(DataLayer.sessionUser(), "email"),
        Type.bitstring("ann@example.org"),
      );
    });

    it("answers nil when the acting user's row isn't held", () => {
      LocalDatabase.actorUserId = "u3";

      assert.deepStrictEqual(DataLayer.sessionUser(), Type.nil());
    });

    it("answers nil for an anonymous session", () => {
      LocalDatabase.actorUserId = null;

      assert.deepStrictEqual(DataLayer.sessionUser(), Type.nil());
    });

    // The server reads no row for a session user id that is not a canonical entity id.
    it("answers nil for an actor id spelled like a member every object inherits", () => {
      LocalDatabase.actorUserId = "constructor";

      assert.deepStrictEqual(DataLayer.sessionUser(), Type.nil());
    });

    // A table reads an undefined key as the string "undefined".
    it("answers nil for an actor id the mount data left out", () => {
      LocalDatabase.putRow(USER, {
        email: "eve@example.com",
        email$sort: "eve@example.com",
        id: "undefined",
      });

      LocalDatabase.actorUserId = undefined;

      assert.deepStrictEqual(DataLayer.sessionUser(), Type.nil());
    });
  });

  describe("stopped()", () => {
    afterEach(() => {
      SyncStream.stopReason = null;
    });

    it("is true once the server stopped serving the tab", () => {
      SyncStream.stopReason = "protocol_version";

      assert.isTrue(DataLayer.stopped());
    });

    it("is false while the server serves it", () => {
      assert.isFalse(DataLayer.stopped());
    });
  });

  describe("streamOpened()", () => {
    it("wakes the sender", () => {
      const flushing = sinon.stub(Batches, "flush");

      DataLayer.streamOpened();

      sinon.assert.calledOnceWithExactly(flushing);
    });
  });
});
