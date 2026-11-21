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
import QueryCheck from "../../assets/js/query_check.mjs";
import QuerySpelling from "../../assets/js/query_spelling.mjs";
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

    // The page carries a count under the field's name and the query it ran, spelled the way the
    // server spells it (see the QuerySpelling tests).
    it("answers a count with the count the page carried under the field's name and its query", () => {
      const term = DataLayer.normalizeQuery(
        ManuallyPortedElixirHologramQueryStage["count/1"](Type.alias(TASK)),
      );

      LocalDatabase.syncCounts = {
        'MyApp.Tasks/total/{"cardinality":"count","entity":"MyApp.Task","filter":[],"include":{},"skip":null,"sort":[],"take":null}': 42,
      };

      assert.deepStrictEqual(
        DataLayer.answerDerivedQuery(
          "MyApp.Tasks",
          Type.atom("total"),
          [],
          term,
        ),
        Type.integer(42),
      );
    });

    const count = ManuallyPortedElixirHologramQueryStage["count/1"];
    const filter = ManuallyPortedElixirHologramQueryStage["filter/2"];
    const sort = ManuallyPortedElixirHologramQueryStage["sort/2"];

    const doneCount = (done) =>
      DataLayer.normalizeQuery(
        count(
          filter(
            Type.alias(TASK),
            Type.list([Type.tuple([Type.atom("done"), Type.boolean(done)])]),
          ),
        ),
      );

    const notDoneCount = () => doneCount(false);

    // The key the page carries the given term's count under.
    const carriedKey = (module, name, term) =>
      `${module}/${name}/${QuerySpelling.spell(term)}`;

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
      LocalDatabase.syncCounts = {
        [carriedKey("MyApp.Complete", "count", notDoneCount())]: 42,
      };
      LocalDatabase.markAllSynced();

      const result = DataLayer.answerDerivedQuery(
        "MyApp.Complete",
        Type.atom("count"),
        [],
        notDoneCount(),
      );

      assert.deepStrictEqual(result, Type.integer(1));
    });

    it("spells no key for a count once the whole pot is complete", () => {
      LocalDatabase.markAllSynced();

      const spell = sinon.spy(QuerySpelling, "spell");

      DataLayer.answerDerivedQuery(
        "MyApp.Complete",
        Type.atom("count"),
        [],
        notDoneCount(),
      );

      sinon.assert.notCalled(spell);
    });

    // The types the server carried with the count, under the count's own key.
    const countReading = (module, types) => {
      LocalDatabase.syncCountTypes = {
        [carriedKey(module, "count", notDoneCount())]: types,
      };
    };

    // Whichever page the component is on, and whether or not the stream connected on it: a type's
    // marker is a claim about the rows the client holds.
    it("counts locally once every type the count reads is complete", () => {
      countReading("MyApp.NavigatedTo", [TASK, "MyApp.Project"]);
      LocalDatabase.syncCounts = {
        [carriedKey("MyApp.NavigatedTo", "count", notDoneCount())]: 42,
      };
      LocalDatabase.markTypesSynced([TASK, "MyApp.Project"]);

      const result = DataLayer.answerDerivedQuery(
        "MyApp.NavigatedTo",
        Type.atom("count"),
        [],
        notDoneCount(),
      );

      assert.deepStrictEqual(result, Type.integer(1));
    });

    it("keeps carrying while a type the count reads is not complete", () => {
      countReading("MyApp.NavigatedTo", [TASK, "MyApp.Project"]);
      LocalDatabase.syncCounts = {
        [carriedKey("MyApp.NavigatedTo", "count", notDoneCount())]: 42,
      };
      LocalDatabase.markTypesSynced([TASK]);

      const result = DataLayer.answerDerivedQuery(
        "MyApp.NavigatedTo",
        Type.atom("count"),
        [],
        notDoneCount(),
      );

      assert.deepStrictEqual(result, Type.integer(42));
    });

    // A tab that took over the stream greets with the page it is on, which may not be the page the
    // completeness it holds was told for (#1582). A type's marker is the same claim on every page,
    // so the count waits for the types it reads, whatever page the stream was greeted with.
    it("keeps carrying on a page reached by a tab that took over while a type the count reads is not complete", () => {
      countReading("MyApp.TakenOverPage", ["MyApp.Project"]);
      LocalDatabase.syncCounts = {
        [carriedKey("MyApp.TakenOverPage", "count", notDoneCount())]: 42,
      };
      LocalDatabase.markTypesSynced([TASK]);

      const result = DataLayer.answerDerivedQuery(
        "MyApp.TakenOverPage",
        Type.atom("count"),
        [],
        notDoneCount(),
      );

      assert.deepStrictEqual(result, Type.integer(42));
    });

    // A count carried with no types can only count on the whole pot.
    it("keeps carrying until everything is complete for a count carried with no types", () => {
      LocalDatabase.syncCounts = {
        [carriedKey("MyApp.Unlisted", "count", notDoneCount())]: 42,
      };
      LocalDatabase.markTypesSynced([TASK]);

      const result = DataLayer.answerDerivedQuery(
        "MyApp.Unlisted",
        Type.atom("count"),
        [],
        notDoneCount(),
      );

      assert.deepStrictEqual(result, Type.integer(42));
    });

    // Two instances of one component answer two counts, and the queries their functions built are
    // what tell them apart.
    it("reads the count of the query the function built", () => {
      LocalDatabase.syncCounts = {
        [carriedKey("MyApp.TwoInstances", "count", doneCount(false))]: 42,
        [carriedKey("MyApp.TwoInstances", "count", doneCount(true))]: 7,
      };

      const result = DataLayer.answerDerivedQuery(
        "MyApp.TwoInstances",
        Type.atom("count"),
        [Type.boolean(true)],
        doneCount(true),
      );

      assert.deepStrictEqual(result, Type.integer(7));
    });

    // The types travel per query, not per field: one instance's types being complete says nothing
    // about another's.
    it("waits for the types the query it ran reads, apart from another instance's", () => {
      const synced = carriedKey("MyApp.TwoReads", "count", doneCount(true));
      const filling = carriedKey("MyApp.TwoReads", "count", doneCount(false));

      LocalDatabase.syncCounts = {[filling]: 42, [synced]: 7};
      LocalDatabase.syncCountTypes = {
        [filling]: ["MyApp.Project"],
        [synced]: [TASK],
      };
      LocalDatabase.markTypesSynced([TASK]);

      const answer = (done) =>
        DataLayer.answerDerivedQuery(
          "MyApp.TwoReads",
          Type.atom("count"),
          [Type.boolean(done)],
          doneCount(done),
        );

      assert.deepStrictEqual(answer(true), Type.integer(1));
      assert.deepStrictEqual(answer(false), Type.integer(42));
    });

    it("leaves a query that does not count alone", () => {
      LocalDatabase.syncCounts = {
        [carriedKey("MyApp.NotCounting", "tasks", sortedByTitle())]: 42,
      };

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

    let joining, leaving, loading, offering, opening;
    let disowning, originalLeader, originalMode, originalName;

    beforeEach(() => {
      originalMode = Durability.mode;
      originalLeader = Tabs.leader;
      originalName = Tabs.name;

      offering = sinon.stub(Replica, "offer");
      opening = sinon.stub(Durability, "open").resolves();
      loading = sinon.stub(Durability, "load").resolves();
      joining = sinon.stub(Tabs, "join").resolves();
      leaving = sinon.stub(Tabs, "leave").resolves();
      disowning = sinon.stub(Batches, "disown");

      sinon.stub(Durability, "databaseName").returns("hologram.1.a3f9c2");
    });

    afterEach(() => {
      Durability.mode = originalMode;
      Tabs.leader = originalLeader;
      Tabs.name = originalName;

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

    // A frame the tab holding the stream stores and posts while this tab starts is either in the
    // store this tab reads or a message it hears - but only if it is listening before it reads.
    it("reads the store once it has joined the group", async () => {
      Durability.mode = "indexeddb";

      let joined;
      joining.returns(new Promise((resolve) => (joined = resolve)));

      const booting = DataLayer.boot(identity());

      await new Promise((resolve) => setTimeout(resolve, 0));

      sinon.assert.calledOnce(joining);
      sinon.assert.notCalled(loading);

      joined(false);
      await booting;

      sinon.assert.calledOnceWithExactly(loading);
    });

    it("reads the store when it joins no group", async () => {
      Durability.mode = "memory";

      await DataLayer.boot(identity());

      sinon.assert.calledOnceWithExactly(loading);
      sinon.assert.notCalled(joining);
    });

    // The store opened, the group was joined, and then the read failed: nothing is left to share,
    // so the tab leads itself as it would had the open failed.
    it("leaves the group when the store could not be read", async () => {
      Durability.mode = "indexeddb";

      loading.callsFake(async () => {
        Durability.mode = "memory";
      });

      joining.callsFake(async (name) => {
        Tabs.name = name;
      });

      await DataLayer.boot(identity());

      sinon.assert.calledOnceWithExactly(leaving);
      assert.isTrue(leaving.calledAfter(loading));
    });

    // Before its mount a tab has made no batch of its own, so whatever it holds came from the group
    // and was numbered under the group's identity - whichever role the tab had when it left.
    for (const leader of [false, true]) {
      it(`lets go of the batches it holds when it ${leader ? "led" : "followed"}`, async () => {
        Durability.mode = "indexeddb";

        loading.callsFake(async () => {
          Durability.mode = "memory";
        });

        joining.callsFake(async (name) => {
          Tabs.leader = leader;
          Tabs.name = name;
        });

        leaving.callsFake(async () => {
          Tabs.leader = true;
          Tabs.name = null;
        });

        await DataLayer.boot(identity());

        sinon.assert.calledOnceWithExactly(disowning);
        assert.isTrue(disowning.calledAfter(leaving));
      });
    }

    it("stays in the group when the store was read", async () => {
      Durability.mode = "indexeddb";

      joining.callsFake(async (name) => {
        Tabs.name = name;
      });

      await DataLayer.boot(identity());

      sinon.assert.notCalled(leaving);
    });

    // A store failure another tab reported ends the group (see Tabs.dissolve), and can do it while
    // this tab is still reading.
    it("leaves no group when a store failure already ended it", async () => {
      Durability.mode = "indexeddb";

      joining.callsFake(async (name) => {
        Tabs.name = name;
      });

      loading.callsFake(async () => {
        Durability.mode = "memory";
        Tabs.name = null;
      });

      await DataLayer.boot(identity());

      sinon.assert.notCalled(leaving);
    });

    // The read comes before the mount, which is what lets the restore after it be synchronous.
    it("resolves only once the store is read", async () => {
      let finishLoad;

      loading.returns(new Promise((resolve) => (finishLoad = resolve)));
      Durability.mode = "indexeddb";

      let booted = false;
      const booting = DataLayer.boot(identity()).then(() => (booted = true));

      await new Promise((resolve) => setImmediate(resolve));
      assert.isFalse(booted);

      finishLoad();
      await booting;

      assert.isTrue(booted);
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
          "filter/3",
          "include/2",
          "include/3",
          "increment/3",
          "normalize/1",
          "one/1",
          "put_attribute/2",
          "put_attribute/3",
          "skip/2",
          "sort/2",
          "sort/3",
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
      LocalDatabase.actorEntityId = null;
      LocalDatabase.syncCountTypes = {};
      LocalDatabase.syncCounts = {};
    });

    afterEach(() => {
      LocalDatabase.actorUserId = null;
      LocalDatabase.actorEntityId = null;
      LocalDatabase.syncCountTypes = {};
      LocalDatabase.syncCounts = {};
    });

    it("files the rows the page carried, and the counts beside them with their types", () => {
      const rows = {put_entity: {"MyApp.Task": [{id: "t1"}]}};

      DataLayer.ingestMountData({
        actorEntityId: "u1",
        actorUserId: "u1",
        syncCountTypes: {"MyApp.Counting/count/": ["MyApp.Task"]},
        syncCounts: {"MyApp.Counting/count/": 3},
        syncRows: rows,
      });

      sinon.assert.calledOnceWithExactly(applying, rows, {insertOnly: true});

      assert.equal(LocalDatabase.actorEntityId, "u1");
      assert.equal(LocalDatabase.actorUserId, "u1");

      assert.deepStrictEqual(LocalDatabase.syncCounts, {
        "MyApp.Counting/count/": 3,
      });

      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {
        "MyApp.Counting/count/": ["MyApp.Task"],
      });
    });

    // The server sends a user id no user entity can have as it is, beside no entity id.
    it("files a user id no user entity can have beside no entity id", () => {
      DataLayer.ingestMountData({
        actorEntityId: null,
        actorUserId: 7,
        syncRows: {},
      });

      assert.isNull(LocalDatabase.actorEntityId);
      assert.equal(LocalDatabase.actorUserId, 7);
    });

    it("takes counts the page did not carry as none", () => {
      LocalDatabase.syncCounts = {"MyApp.Stale/count/": 9};
      LocalDatabase.syncCountTypes = {"MyApp.Stale/count/": ["MyApp.Task"]};

      DataLayer.ingestMountData({actorUserId: null, syncRows: {}});

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {});
    });

    it("leaves the database as it was for mount data carrying no rows", () => {
      LocalDatabase.syncCounts = {"MyApp.Held/count/": 9};

      DataLayer.ingestMountData({actorUserId: "u1", syncCounts: {}});

      sinon.assert.notCalled(applying);

      assert.isNull(LocalDatabase.actorUserId);
      assert.isNull(LocalDatabase.actorEntityId);
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

  describe("queryRefusal()", () => {
    it("answers why the browser can't answer a query, as QueryCheck does", () => {
      globalThis.Hologram.sync = {
        model: {
          "MyApp.Task": {
            attributes: {id: "uuid", token: "string"},
            relationships: {},
            serverOnly: ["token"],
          },
        },
      };

      Model.reset();

      const term = {
        cardinality: "set",
        entity: "MyApp.Task",
        filter: [["token", "==", "x"]],
        include: {},
        skip: null,
        sort: [],
        take: null,
      };

      assert.strictEqual(
        DataLayer.queryRefusal(term),
        QueryCheck.refusal(term),
      );
      assert.match(DataLayer.queryRefusal(term), /^filters or sorts/);
    });

    // In the order the server refuses them: what the browser may not hold, then what sync never
    // sends.
    it("refuses a type sync never sends once nothing else is refused", () => {
      globalThis.Hologram.sync = {
        model: {
          "MyApp.Task": {
            attributes: {id: "uuid", token: "string"},
            relationships: {},
            serverOnly: ["token"],
          },
        },
        syncedTypes: [],
      };

      Model.reset();

      const term = (filter) => ({
        cardinality: "set",
        entity: "MyApp.Task",
        filter,
        include: {},
        skip: null,
        sort: [],
        take: null,
      });

      assert.match(
        DataLayer.queryRefusal(term([["token", "==", "x"]])),
        /^filters or sorts/,
      );

      assert.match(
        DataLayer.queryRefusal(term([])),
        /^reads MyApp\.Task, which browser code never names/,
      );
    });

    describe("its cache", () => {
      const term = (filter) => ({
        cardinality: "set",
        entity: "MyApp.Task",
        filter,
        include: {},
        skip: null,
        sort: [],
        take: null,
      });

      beforeEach(() => {
        globalThis.Hologram.sync = {
          model: {
            "MyApp.Task": {
              attributes: {id: "uuid", title: "string"},
              relationships: {},
              serverOnly: [],
            },
          },
          syncedTypes: ["MyApp.Task"],
        };

        Model.reset();
      });

      // Every render asks again, so a query spelled alike - whatever object holds it - is answered
      // from what the first ask worked out.
      it("works out a query spelled alike once", () => {
        const refusal = sinon.spy(QueryCheck, "refusal");

        assert.isNull(DataLayer.queryRefusal(term([["title", "==", "x"]])));
        assert.isNull(DataLayer.queryRefusal(term([["title", "==", "x"]])));

        sinon.assert.calledOnce(refusal);
      });

      it("works out a query spelled otherwise anew", () => {
        const refusal = sinon.spy(QueryCheck, "refusal");

        DataLayer.queryRefusal(term([["title", "==", "x"]]));
        DataLayer.queryRefusal(term([["title", "==", "y"]]));

        sinon.assert.calledTwice(refusal);
      });

      it("works out anew once the synced types change", () => {
        assert.isNull(DataLayer.queryRefusal(term([])));

        globalThis.Hologram.sync.syncedTypes = [];

        assert.match(DataLayer.queryRefusal(term([])), /^reads MyApp\.Task/);
      });

      // A rules frame reads the model afresh, which can make an attribute server-only.
      it("works out anew once the model is read afresh", () => {
        const query = term([["title", "==", "x"]]);

        assert.isNull(DataLayer.queryRefusal(query));

        globalThis.Hologram.sync.model["MyApp.Task"].serverOnly = ["title"];
        Model.reset();

        assert.match(DataLayer.queryRefusal(query), /^filters or sorts/);
      });
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
            attributes: {
              email: "string",
              id: "uuid",
              password_hash: "string",
            },
            relationships: {},
            serverOnly: ["password_hash"],
          },
        },
        userEntity: USER,
      };

      Model.reset();
      LocalDatabase.reset();
      LocalDatabase.actorUserId = "u1";
      LocalDatabase.actorEntityId = "u1";

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
      LocalDatabase.actorEntityId = null;
      Overlay.reset();
      delete globalThis.Hologram.sync;
    });

    // The server reads a user id no user entity can have as no session user, even one spelled like
    // a row's id, so this does too.
    it("answers nil for a user id no user entity can have", () => {
      LocalDatabase.actorEntityId = null;

      assert.deepStrictEqual(DataLayer.sessionUser(), Type.nil());
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
      LocalDatabase.actorEntityId = "u3";

      assert.deepStrictEqual(DataLayer.sessionUser(), Type.nil());
    });

    it("answers nil for an anonymous session", () => {
      LocalDatabase.actorUserId = null;
      LocalDatabase.actorEntityId = null;

      assert.deepStrictEqual(DataLayer.sessionUser(), Type.nil());
    });

    // The server reads no row for a session user id that is not a canonical entity id.
    it("answers nil for an actor id spelled like a member every object inherits", () => {
      LocalDatabase.actorUserId = "constructor";
      LocalDatabase.actorEntityId = "constructor";

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
      LocalDatabase.actorEntityId = undefined;

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
