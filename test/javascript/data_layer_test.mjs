"use strict";

import {assert, defineRuntimeGlobals, sinon} from "./support/helpers.mjs";

import Batch from "../../assets/js/batch.mjs";
import Batches from "../../assets/js/batches.mjs";
import Client from "../../assets/js/client.mjs";
import DataLayer from "../../assets/js/data_layer.mjs";
import Deltas from "../../assets/js/deltas.mjs";
import Durability from "../../assets/js/durability.mjs";
import IdentityTracker from "../../assets/js/identity_tracker.mjs";
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
import Sse from "../../assets/js/sse.mjs";
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

    // Back or Forward reads no mount data, so a page it returns to has only what earlier visits
    // left.
    describe("after another page's mount data", () => {
      const answerTotal = (term) =>
        DataLayer.answerDerivedQuery(
          "MyApp.Tasks",
          Type.atom("total"),
          [],
          term,
        );

      const visitPages = (term) => {
        const key = `MyApp.Tasks/total/${QuerySpelling.spell(term)}`;

        sinon.stub(Deltas, "apply");

        DataLayer.ingestMountData({
          actorUserId: null,
          syncCountTypes: {[key]: [TASK]},
          syncCounts: {[key]: 42},
          syncRows: {},
        });

        DataLayer.ingestMountData({
          actorUserId: null,
          syncCountTypes: {},
          syncCounts: {},
          syncRows: {},
        });
      };

      it("still answers the carried count while the type is filling", () => {
        const term = DataLayer.normalizeQuery(
          ManuallyPortedElixirHologramQueryStage["count/1"](Type.alias(TASK)),
        );

        visitPages(term);

        assert.deepStrictEqual(answerTotal(term), Type.integer(42));
      });

      it("counts locally once the client holds the whole type", () => {
        const term = DataLayer.normalizeQuery(
          ManuallyPortedElixirHologramQueryStage["count/1"](Type.alias(TASK)),
        );

        visitPages(term);
        LocalDatabase.markTypesSynced([TASK]);

        assert.deepStrictEqual(answerTotal(term), Type.integer(2));
      });
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

    // What the stream's handshake is held to (see takeHandshake).
    it("follows the identity the document was rendered for", async () => {
      const originalTag = IdentityTracker.tag;
      Durability.mode = "memory";
      IdentityTracker.tag = "3.tag-3";

      try {
        await DataLayer.boot(identity());

        assert.equal(SyncStream.followedTag, "3.tag-3");
      } finally {
        IdentityTracker.tag = originalTag;
        SyncStream.followedTag = null;
      }
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

    let originalPeriod;

    beforeEach(() => {
      applying = sinon.stub(Deltas, "apply");

      originalPeriod = IdentityTracker.period;
      IdentityTracker.period = null;

      LocalDatabase.actorUserId = null;
      LocalDatabase.actorEntityId = null;
      LocalDatabase.syncCountTypes = {};
      LocalDatabase.syncCounts = {};
      LocalDatabase.syncCountsPeriod = null;
    });

    afterEach(() => {
      IdentityTracker.period = originalPeriod;

      LocalDatabase.actorUserId = null;
      LocalDatabase.actorEntityId = null;
      LocalDatabase.syncCountTypes = {};
      LocalDatabase.syncCounts = {};
      LocalDatabase.syncCountsPeriod = null;
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

    it("keeps the counts an earlier page carried", () => {
      LocalDatabase.syncCounts = {"MyApp.Earlier/count/": 9};
      LocalDatabase.syncCountTypes = {"MyApp.Earlier/count/": ["MyApp.Task"]};

      DataLayer.ingestMountData({
        actorUserId: null,
        syncCountTypes: {"MyApp.Later/count/": ["MyApp.Task"]},
        syncCounts: {"MyApp.Later/count/": 3},
        syncRows: {},
      });

      assert.deepStrictEqual(LocalDatabase.syncCounts, {
        "MyApp.Earlier/count/": 9,
        "MyApp.Later/count/": 3,
      });

      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {
        "MyApp.Earlier/count/": ["MyApp.Task"],
        "MyApp.Later/count/": ["MyApp.Task"],
      });
    });

    it("keeps the earlier counts for mount data carrying no counts", () => {
      LocalDatabase.syncCounts = {"MyApp.Earlier/count/": 9};
      LocalDatabase.syncCountTypes = {"MyApp.Earlier/count/": ["MyApp.Task"]};

      DataLayer.ingestMountData({actorUserId: null, syncRows: {}});

      assert.deepStrictEqual(LocalDatabase.syncCounts, {
        "MyApp.Earlier/count/": 9,
      });
    });

    it("takes a newer number and its types for a count already held", () => {
      LocalDatabase.syncCounts = {"MyApp.Held/count/": 9};
      LocalDatabase.syncCountTypes = {"MyApp.Held/count/": ["MyApp.Task"]};

      DataLayer.ingestMountData({
        actorUserId: null,
        syncCountTypes: {"MyApp.Held/count/": ["MyApp.Note"]},
        syncCounts: {"MyApp.Held/count/": 10},
        syncRows: {},
      });

      assert.deepStrictEqual(LocalDatabase.syncCounts, {
        "MyApp.Held/count/": 10,
      });

      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {
        "MyApp.Held/count/": ["MyApp.Note"],
      });
    });

    it("drops the earlier counts when the page is for another user", () => {
      LocalDatabase.actorUserId = "u1";
      LocalDatabase.syncCounts = {"MyApp.Earlier/count/": 9};
      LocalDatabase.syncCountTypes = {"MyApp.Earlier/count/": ["MyApp.Task"]};

      DataLayer.ingestMountData({
        actorUserId: "u2",
        syncCountTypes: {"MyApp.Later/count/": ["MyApp.Task"]},
        syncCounts: {"MyApp.Later/count/": 3},
        syncRows: {},
      });

      assert.deepStrictEqual(LocalDatabase.syncCounts, {
        "MyApp.Later/count/": 3,
      });

      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {
        "MyApp.Later/count/": ["MyApp.Task"],
      });
    });

    // A user who signed out and back in has one id, so only the period tells the two visits apart.
    it("drops the earlier counts when the identity period changed under the same id", () => {
      LocalDatabase.actorUserId = "u1";
      LocalDatabase.syncCounts = {"MyApp.Earlier/count/": 9};
      LocalDatabase.syncCountTypes = {"MyApp.Earlier/count/": ["MyApp.Task"]};

      IdentityTracker.period = "period-2";

      DataLayer.ingestMountData({
        actorUserId: "u1",
        syncRows: {},
      });

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {});
      assert.equal(LocalDatabase.syncCountsPeriod, "period-2");
    });

    // The identity can change between a page arriving and its mount, so a count the old identity's
    // page carried must not pass for the new one's.
    it("files a late page's counts under the period it was rendered in", () => {
      IdentityTracker.period = "period-2";

      DataLayer.ingestMountData({
        actorUserId: 9007199254740992,
        identityPeriod: "period-1",
        syncCountTypes: {"MyApp.Late/count/": ["MyApp.Task"]},
        syncCounts: {"MyApp.Late/count/": 42},
        syncRows: {},
      });

      assert.equal(LocalDatabase.syncCountsPeriod, "period-1");

      DataLayer.ingestMountData({
        actorUserId: 9007199254740992,
        identityPeriod: "period-2",
        syncRows: {},
      });

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {});
    });

    it("keeps the earlier counts while the identity period lasts", () => {
      IdentityTracker.period = "period-1";
      LocalDatabase.syncCountsPeriod = "period-1";
      LocalDatabase.syncCounts = {"MyApp.Earlier/count/": 9};

      DataLayer.ingestMountData({actorUserId: null, syncRows: {}});

      assert.deepStrictEqual(LocalDatabase.syncCounts, {
        "MyApp.Earlier/count/": 9,
      });
    });

    it("drops the earlier counts when a visitor signs in", () => {
      LocalDatabase.syncCounts = {"MyApp.Earlier/count/": 9};

      DataLayer.ingestMountData({actorUserId: "u1", syncRows: {}});

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
    });

    it("drops the earlier counts when the user signs out", () => {
      LocalDatabase.actorUserId = "u1";
      LocalDatabase.syncCounts = {"MyApp.Earlier/count/": 9};

      DataLayer.ingestMountData({actorUserId: null, syncRows: {}});

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
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

  describe("holdsOtherUser()", () => {
    afterEach(() => {
      DataLayer.isStoreRestored = false;
      LocalDatabase.actorUserId = null;
    });

    it("is true for another user once the store is read", () => {
      DataLayer.isStoreRestored = true;
      LocalDatabase.actorUserId = "u1";

      assert.isTrue(DataLayer.holdsOtherUser("u2"));
    });

    it("is false for the user it holds", () => {
      DataLayer.isStoreRestored = true;
      LocalDatabase.actorUserId = "u1";

      assert.isFalse(DataLayer.holdsOtherUser("u1"));
    });

    it("takes undefined and null as the same visitor", () => {
      DataLayer.isStoreRestored = true;
      LocalDatabase.actorUserId = undefined;

      assert.isFalse(DataLayer.holdsOtherUser(null));
    });

    // The document's first mount is what says who it is for.
    it("is false before the store is read", () => {
      LocalDatabase.actorUserId = "u1";

      assert.isFalse(DataLayer.holdsOtherUser("u2"));
    });
  });

  describe("followIdentity()", () => {
    const TASK = "MyApp.Task";

    const pair = {id: "replica-2", token: "token-2"};

    const sealed = (id) => {
      Batches.open("tasks");
      Batches.current().append({id, op: "delete", stamp: 1, type: TASK});

      return Batches.close();
    };

    let originalTracker, persisting, rendering;

    beforeEach(() => {
      originalTracker = {
        documentPeriod: IdentityTracker.documentPeriod,
        period: IdentityTracker.period,
        periods: IdentityTracker.periods,
        tag: IdentityTracker.tag,
      };

      globalThis.Hologram.sync = {
        model: {
          [TASK]: {
            attributes: {id: "uuid", title: "string"},
            relationships: {},
            serverOnly: [],
          },
        },
      };

      Model.reset();
      Batches.reset();
      Replica.reset();
      LocalDatabase.reset();
      IdentityTracker.init("1.tag-1");

      LocalDatabase.identityEndedPeriod = null;
      LocalDatabase.actorUserId = "u1";
      LocalDatabase.actorEntityId = "entity-1";
      LocalDatabase.putRow(TASK, {id: "t1", title: "the first user's"});

      SyncStream.followedTag = null;
      SyncStream.rowsChangedSinceRender = false;
      SyncStream.syncCursor = "place-1";

      Replica.adopt({id: "replica-1", token: "token-1"});

      persisting = sinon.stub(Durability, "persistReplica");
      rendering = sinon.stub(SyncStream, "scheduleRender");
    });

    afterEach(() => {
      Object.assign(IdentityTracker, originalTracker);

      Batches.reset();
      Replica.reset();
      LocalDatabase.reset();

      LocalDatabase.identityEndedPeriod = null;
      LocalDatabase.actorUserId = null;
      LocalDatabase.actorEntityId = null;

      SyncStream.awaitingIdentity = false;
      SyncStream.awaitingPair = false;
      SyncStream.followedTag = null;
      SyncStream.laggingCookie = false;
      SyncStream.rowsChangedSinceRender = false;
      SyncStream.syncCursor = null;

      Tabs.leader = true;
      Tabs.name = null;
      Tabs.takingLead = false;

      delete globalThis.Hologram.sync;
    });

    const followToSecondUser = (fields = {}, options) =>
      DataLayer.followIdentity(
        {
          actorEntityId: "entity-2",
          actorUserId: "u2",
          identityTag: "2.tag-2",
          ...fields,
        },
        options,
      );

    // A tab in a group, for what a follow does before the move is under way.
    const inGroup = (follow) => {
      const originalMode = Durability.mode;

      Durability.mode = "indexeddb";
      Tabs.name = "hologram.1.model.u1";

      sinon.stub(Tabs, "move").returns(new Promise(() => {}));

      try {
        follow();
      } finally {
        Durability.mode = originalMode;
        Tabs.name = null;
      }
    };

    describe("to another user", () => {
      it("drops the previous user's rows", () => {
        followToSecondUser();

        assert.isNull(LocalDatabase.getRow(TASK, "t1"));
      });

      it("answers for the new user", () => {
        followToSecondUser();

        assert.equal(LocalDatabase.actorUserId, "u2");
        assert.equal(LocalDatabase.actorEntityId, "entity-2");
      });

      it("takes a sign-out as nobody", () => {
        followToSecondUser({actorEntityId: undefined, actorUserId: null});

        assert.isNull(LocalDatabase.actorUserId);
        assert.isNull(LocalDatabase.actorEntityId);
      });

      it("gives up the place, which dated the previous user's rows", () => {
        followToSecondUser();

        assert.isNull(SyncStream.syncCursor);
      });

      it("has the next action compute its fields again and asks for a render", () => {
        followToSecondUser();

        assert.isTrue(SyncStream.rowsChangedSinceRender);
        sinon.assert.calledOnce(rendering);
      });

      it("takes in the new user's own row", () => {
        const applying = sinon.stub(Deltas, "apply");
        const userRow = {put_entity: {"MyApp.User": [{id: "entity-2"}]}};

        followToSecondUser({userRow});

        sinon.assert.calledOnceWithExactly(applying, userRow, {
          insertOnly: true,
        });
      });

      it("lets the previous user's batches go", () => {
        sealed("t2");

        followToSecondUser();

        assert.deepStrictEqual(Batches.pending, []);
        assert.isFalse(Overlay.names(TASK, "t2"));
      });

      it("answers that it moved the tab", () => {
        assert.isTrue(followToSecondUser());
      });

      // The store or the new user's group hands it the new user's pair once the move settles.
      it("holds no pair in a group", () => {
        Replica.fresh = {id: "replica-1", token: "token-1"};

        inGroup(() => followToSecondUser());

        assert.isNull(Replica.id);
        assert.isNull(Replica.fresh);
        assert.isTrue(SyncStream.holdsWrites());
      });

      // The stream's listener opens a new one, whose handshake hands the tab a pair of its own.
      describe("in no group", () => {
        let reconnecting, wasStarted;

        beforeEach(() => {
          wasStarted = Sse.isStarted;
          Sse.isStarted = true;

          reconnecting = sinon.stub(Sse, "reconnect");
        });

        afterEach(() => {
          Sse.isStarted = wasStarted;
        });

        it("holds no pair", () => {
          Replica.fresh = {id: "replica-1", token: "token-1"};

          followToSecondUser();

          assert.isNull(Replica.id);
          assert.isNull(Replica.token);
          assert.isNull(Replica.fresh);
          assert.isTrue(SyncStream.holdsWrites());
        });

        // Left to the caller: a handshake's follow opens the stream it was made for.
        it("opens no stream itself", () => {
          followToSecondUser();

          sinon.assert.notCalled(reconnecting);
        });

        // The follow drops the pair the tab held, and the handshake that told it of the new user
        // hands it the new one.
        it("takes the pair of a handshake that tells it of the new user", () => {
          DataLayer.takeHandshake({
            actorEntityId: "entity-2",
            actorUserId: "u2",
            identityTag: "2.tag-2",
            replica: pair,
          });

          assert.equal(LocalDatabase.actorUserId, "u2");
          assert.deepStrictEqual(Replica.current(), pair);
          assert.deepStrictEqual(Replica.fresh, pair);
          assert.isFalse(SyncStream.holdsWrites());
        });
      });

      // The move settles a lead before the tab sends, and the lead reads the new user's pair from
      // the store, where a pair taken up now would be written over it.
      it("takes no pair from a handshake that moves it to the new user's group", () => {
        const originalMode = Durability.mode;

        Durability.mode = "indexeddb";
        Tabs.name = "hologram.1.model.u1";

        // A move whose lock was granted at once, before its lead settles: a tab still waiting for
        // the lock is a follower, which takes no pair anyway.
        sinon.stub(Tabs, "move").callsFake((name) => {
          Tabs.name = name;
          Tabs.leader = true;
          Tabs.takingLead = true;

          return new Promise(() => {});
        });

        try {
          DataLayer.takeHandshake({
            actorEntityId: "entity-2",
            actorUserId: "u2",
            identityTag: "2.tag-2",
            replica: pair,
          });

          assert.isNull(Replica.id);
          assert.deepStrictEqual(Replica.fresh, pair);
          sinon.assert.notCalled(persisting);
        } finally {
          Durability.mode = originalMode;
        }
      });

      it("goes on waiting for a pair", () => {
        SyncStream.awaitingPair = true;

        followToSecondUser();

        assert.isTrue(SyncStream.awaitingPair);
      });

      // The previous user's pair would be sent under the new user's session, or written into
      // their slot, and the page offered it for the previous user too.
      it("holds no pair", () => {
        Replica.fresh = {id: "replica-1", token: "token-1"};

        followToSecondUser();

        assert.isNull(Replica.id);
        assert.isNull(Replica.token);
        assert.isNull(Replica.fresh);
      });

      // With no pair a send could only be refused.
      it("waits for a pair", () => {
        followToSecondUser();

        assert.isTrue(SyncStream.holdsWrites());
      });

      it("holds the pair slot for the new user", () => {
        Replica.owner = "u1";

        followToSecondUser();

        assert.equal(Replica.owner, "u2");
      });

      it("stays in no group when the tab is in none", () => {
        const moving = sinon.stub(Tabs, "move").resolves(null);

        followToSecondUser();

        sinon.assert.notCalled(moving);
      });

      // What the previous user's group shares is theirs: their store's claim, their pair, their
      // queue.
      describe("in a group", () => {
        const resumed = {
          batches: [{seq: 4, writes: []}],
          cursor: "place-2",
          readForeign: true,
          seq: 5,
        };

        const visit = {};

        let adopting,
          dissolving,
          flushing,
          loading,
          moving,
          posting,
          readying,
          reconnecting,
          restoring,
          resumingFrom,
          wasMode,
          wasStarted;

        beforeEach(() => {
          wasMode = Durability.mode;
          wasStarted = Sse.isStarted;

          Durability.mode = "indexeddb";
          Sse.isStarted = true;
          Tabs.name = "hologram.1.model.u1";

          adopting = sinon.stub(Batches, "adopt");
          dissolving = sinon.stub(Tabs, "dissolve");
          flushing = sinon.stub(Batches, "flush");
          loading = sinon.stub(Durability, "load").resolves();
          moving = sinon.stub(Tabs, "move").resolves(visit);
          posting = sinon.stub(Tabs, "post");
          readying = sinon.stub(Tabs, "ready");
          reconnecting = sinon.stub(Sse, "reconnect");
          restoring = sinon.stub(Durability, "restore").returns(resumed);
          resumingFrom = sinon.stub(Batches, "resumeFrom");

          sinon.stub(Tabs, "isVisit").callsFake((given) => given === visit);
        });

        afterEach(() => {
          Durability.mode = wasMode;
          Sse.isStarted = wasStarted;
          Tabs.name = null;
          SyncStream.heldSync = false;
        });

        const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

        it("moves the tab to the new user's group", async () => {
          followToSecondUser();
          await settle();

          sinon.assert.calledOnceWithExactly(
            moving,
            Durability.groupName("u2"),
          );
        });

        // Joined first, read after, as a page load does.
        it("takes up what the store holds for the new user", async () => {
          Tabs.leader = false;

          followToSecondUser();
          await settle();

          assert.isTrue(moving.calledBefore(loading));
          sinon.assert.calledOnceWithExactly(restoring, false);
          sinon.assert.calledOnceWithExactly(resumingFrom, 5);
          sinon.assert.calledOnceWithExactly(adopting, resumed.batches);
          sinon.assert.calledOnceWithExactly(readying, true);
          sinon.assert.calledOnceWithExactly(posting, {kind: "joined"});
          sinon.assert.calledOnce(flushing);

          assert.equal(SyncStream.syncCursor, "place-2");
        });

        // Only the current visit's read counts: a newer move loads again.
        it("reads the store for the visit it moved to", async () => {
          followToSecondUser();
          await settle();

          const isCurrent = loading.firstCall.args[0];

          assert.isTrue(isCurrent());

          Tabs.isVisit.callsFake(() => false);

          assert.isFalse(isCurrent());
        });

        it("asks for sync again when it leads the new group", async () => {
          followToSecondUser();
          await settle();

          sinon.assert.calledOnce(reconnecting);
        });

        it("closes the sync session its stream held when it follows", async () => {
          SyncStream.heldSync = true;
          Tabs.leader = false;

          followToSecondUser();
          await settle();

          sinon.assert.calledOnce(reconnecting);
        });

        // A follow a handshake made: the stream that handshake opens replaces the one that held it.
        it("leaves a sync session to the caller that says it's closed", async () => {
          SyncStream.heldSync = true;
          Tabs.leader = false;

          followToSecondUser({}, {heldSync: false});
          await settle();

          sinon.assert.notCalled(reconnecting);
        });

        // The lock came to it while it read, so it judges the store as the tab that leads, and the
        // lead it takes at ready() opens its own stream.
        it("takes up the store as the leader when handed the lead while it read", async () => {
          Tabs.leader = false;

          loading.callsFake(async () => {
            Tabs.leader = true;
          });

          followToSecondUser();
          await settle();

          sinon.assert.calledOnceWithExactly(restoring, true);
          sinon.assert.notCalled(reconnecting);
        });

        it("leaves the stream to a lead handed over while it read, though it held sync", async () => {
          Tabs.leader = false;
          SyncStream.heldSync = true;

          loading.callsFake(async () => {
            Tabs.leader = true;
          });

          followToSecondUser();
          await settle();

          sinon.assert.notCalled(reconnecting);
        });

        it("keeps a stream that held no sync when it follows", async () => {
          Tabs.leader = false;

          followToSecondUser();
          await settle();

          sinon.assert.notCalled(reconnecting);
        });

        // The page opens one after the mount, which greets as the tab now stands.
        it("opens no stream before the page has", async () => {
          Sse.isStarted = false;

          followToSecondUser();
          await settle();

          sinon.assert.notCalled(reconnecting);
        });

        it("stops when a newer move took the tab elsewhere while it joined", async () => {
          moving.resolves(null);

          followToSecondUser();
          await settle();

          sinon.assert.notCalled(loading);
          sinon.assert.notCalled(restoring);
        });

        it("takes up nothing when a newer move took the tab elsewhere while it read", async () => {
          loading.callsFake(async () => {
            Tabs.isVisit.callsFake(() => false);
          });

          followToSecondUser();
          await settle();

          sinon.assert.notCalled(restoring);
          sinon.assert.notCalled(readying);
          sinon.assert.notCalled(reconnecting);
        });

        describe("when the store already stopped", () => {
          let disowning, leaving;

          beforeEach(() => {
            disowning = sinon.stub(Batches, "disown");
            leaving = sinon.stub(Tabs, "leave");

            Durability.mode = "memory";
          });

          // Joined, it could lead the new user's tabs from memory.
          it("leaves its group and joins no other", async () => {
            followToSecondUser();
            await settle();

            sinon.assert.calledOnce(leaving);
            sinon.assert.notCalled(moving);
            sinon.assert.notCalled(loading);
          });

          // The ones it made since the store stopped were never stored.
          it("keeps the batches it holds", async () => {
            followToSecondUser();
            await settle();

            sinon.assert.notCalled(disowning);
          });

          it("asks for sync as a replica of its own", async () => {
            Tabs.leader = false;

            followToSecondUser();
            await settle();

            sinon.assert.calledOnce(reconnecting);
          });

          // It left its group, so the group's pair isn't its to send under: its reconnect's
          // handshake hands it one of its own.
          it("holds no pair until its own stream hands it one", async () => {
            followToSecondUser();
            await settle();

            assert.isNull(Replica.id);
            assert.isNull(Replica.fresh);
            assert.isTrue(SyncStream.holdsWrites());
          });
        });

        describe("when the store can't be read", () => {
          let disowning, leaving;

          beforeEach(() => {
            disowning = sinon.stub(Batches, "disownStored");
            leaving = sinon.stub(Tabs, "leave");

            loading.callsFake(async () => {
              Durability.mode = "memory";
            });
          });

          // As at boot: with nothing stored, there is nothing to share.
          it("leaves the group", async () => {
            followToSecondUser();
            await settle();

            sinon.assert.calledOnce(leaving);
            sinon.assert.notCalled(restoring);
          });

          // They're in the store, where another tab sends them under its own pair.
          it("lets go of the batches the store holds, though it leads", async () => {
            followToSecondUser();
            await settle();

            sinon.assert.calledOnce(disowning);
            sinon.assert.notCalled(dissolving);
          });

          // A filing still out decides whether its batch is one the store holds.
          it("lets go of them once its filings settle", async () => {
            let filed;

            sinon
              .stub(Batches, "recorded")
              .returns(new Promise((resolve) => (filed = resolve)));

            followToSecondUser();
            await settle();

            sinon.assert.notCalled(disowning);

            filed();
            await settle();

            sinon.assert.calledOnce(disowning);
          });

          it("leaves them to a newer follow made while its filings settle", async () => {
            let filed;

            sinon
              .stub(Batches, "recorded")
              .returns(new Promise((resolve) => (filed = resolve)));

            followToSecondUser();
            await settle();

            Tabs.isVisit.callsFake(() => false);
            filed();
            await settle();

            sinon.assert.notCalled(disowning);
          });

          it("asks for sync as a replica of its own", async () => {
            Tabs.leader = false;

            followToSecondUser();
            await settle();

            sinon.assert.calledOnce(reconnecting);
          });

          it("holds no pair until its own stream hands it one", async () => {
            followToSecondUser();
            await settle();

            assert.isNull(Replica.id);
            assert.isNull(Replica.fresh);
            assert.isTrue(SyncStream.holdsWrites());
          });
        });

        it("stays in its group for the same user", async () => {
          DataLayer.followIdentity({
            actorEntityId: "entity-1",
            actorUserId: "u1",
            identityTag: "1.tag-1",
          });

          await settle();

          sinon.assert.notCalled(moving);
        });
      });

      it("moves to the new identity's period", () => {
        const period = IdentityTracker.period;

        followToSecondUser();

        assert.equal(IdentityTracker.tag, "2.tag-2");
        assert.notEqual(IdentityTracker.period, period);
      });

      // Counts are filed under the period, and the new user's has only just begun.
      it("doesn't count the new user's period as ended", () => {
        followToSecondUser();

        assert.isNull(LocalDatabase.identityEndedPeriod);
      });

      // A login command's reply can have moved the period before the stream said so.
      it("doesn't end a period a response already moved to", () => {
        IdentityTracker.observe("2.tag-2");

        followToSecondUser();

        assert.isNull(LocalDatabase.identityEndedPeriod);
      });

      // With no tag the period can't move, and it held the previous user's numbers.
      it("counts the period as ended when the server tags nothing", () => {
        followToSecondUser({identityTag: undefined});

        assert.equal(LocalDatabase.identityEndedPeriod, IdentityTracker.period);
      });

      describe("named by an event no newer than what the tab knows", () => {
        let reconnecting, settling;

        beforeEach(() => {
          IdentityTracker.init("5.tag");
          LocalDatabase.actorUserId = "u1";
          settling = sinon.stub(Client, "settleIdentity").resolves();
          reconnecting = sinon.stub(Sse, "reconnect");
        });

        afterEach(() => {
          settling.restore();
          reconnecting.restore();
          SyncStream.awaitingIdentity = false;
        });

        const followBehind = () =>
          DataLayer.followIdentity({
            actorEntityId: "entity-2",
            actorUserId: "u2",
            identityTag: "4.other",
          });

        it("stays with the user it holds", () => {
          followBehind();

          assert.equal(LocalDatabase.actorUserId, "u1");
          assert.equal(IdentityTracker.tag, "5.tag");
        });

        // The settle opens the stream, so the caller mustn't open another.
        it("answers that it didn't move the tab", () => {
          assert.isFalse(followBehind());
        });

        // The stream's server side has moved to that identity all the same.
        it("takes nothing more from this stream", () => {
          followBehind();

          assert.isTrue(SyncStream.awaitingIdentity);
        });

        it("opens a new stream once the server has said who is signed in", async () => {
          followBehind();

          sinon.assert.calledOnce(settling);
          sinon.assert.notCalled(reconnecting);

          await settling.firstCall.returnValue;
          await Promise.resolve();

          sinon.assert.calledOnce(reconnecting);
        });
      });

      it("remembers the tag it followed", () => {
        followToSecondUser();

        assert.equal(SyncStream.followedTag, "2.tag-2");
      });

      it("treats a visitor named undefined as a visitor", () => {
        LocalDatabase.actorUserId = undefined;

        DataLayer.followIdentity({actorUserId: null, identityTag: "2.tag-2"});

        assert.isNotNull(LocalDatabase.getRow(TASK, "t1"));
      });
    });

    describe("to the same user", () => {
      const followToSameUser = (fields = {}) =>
        DataLayer.followIdentity({
          actorEntityId: "entity-1",
          actorUserId: "u1",
          identityTag: "1.tag-1",
          ...fields,
        });

      it("keeps the rows and the place", () => {
        followToSameUser();

        assert.isNotNull(LocalDatabase.getRow(TASK, "t1"));
        assert.equal(SyncStream.syncCursor, "place-1");
        sinon.assert.notCalled(rendering);
      });

      it("keeps the pair", () => {
        followToSameUser();

        assert.equal(Replica.id, "replica-1");
        sinon.assert.notCalled(persisting);
      });

      it("answers that it didn't move the tab", () => {
        assert.isFalse(followToSameUser());
      });
    });

    describe("from a page's mount data", () => {
      let reconnecting;

      const mount = (actorUserId) =>
        DataLayer.ingestMountData({
          actorEntityId: "entity-2",
          actorUserId,
          identityPeriod: IdentityTracker.period,
          syncRows: {},
        });

      beforeEach(() => {
        DataLayer.isStoreRestored = true;
        Sse.isStarted = true;
        reconnecting = sinon.stub(Sse, "reconnect");
      });

      afterEach(() => {
        // Run while the stub is in place, so a test that mounted leaves no stream to replace.
        DataLayer.reconnectIfFollowed();

        DataLayer.isStoreRestored = false;
        Sse.isStarted = false;
      });

      it("follows a user the page was rendered for", () => {
        mount("u2");

        assert.equal(LocalDatabase.actorUserId, "u2");
        assert.isNull(LocalDatabase.getRow(TASK, "t1"));
      });

      it("drops the frames of the stream it had", () => {
        mount("u2");

        assert.isTrue(SyncStream.awaitingIdentity);
      });

      // Its response carries no pair.
      it("holds writes until it has a pair", () => {
        mount("u2");

        assert.isTrue(SyncStream.holdsWrites());
      });

      // The handshake presents the page's receipts, which the mount has yet to take in.
      it("opens a new stream only once the mount is done", () => {
        mount("u2");

        sinon.assert.notCalled(reconnecting);

        DataLayer.restore();

        sinon.assert.calledOnce(reconnecting);
      });

      it("opens one new stream per follow", () => {
        mount("u2");

        DataLayer.restore();
        DataLayer.restore();

        sinon.assert.calledOnce(reconnecting);
      });

      it("opens none before the stream has started", () => {
        Sse.isStarted = false;

        mount("u2");
        DataLayer.restore();

        sinon.assert.notCalled(reconnecting);
      });

      // A mount that raises doesn't reach the store's restore.
      it("replaces the stream when asked after a mount that raised", () => {
        mount("u2");

        DataLayer.reconnectIfFollowed();

        sinon.assert.calledOnce(reconnecting);
      });

      // The response's tag was observed already, and the new user's period has only just begun.
      it("doesn't count the new user's period as ended", () => {
        IdentityTracker.observe("2.tag-2");

        mount("u2");

        assert.isNull(LocalDatabase.identityEndedPeriod);
      });

      it("does nothing for the user it already holds", () => {
        mount("u1");
        DataLayer.restore();

        assert.isNotNull(LocalDatabase.getRow(TASK, "t1"));
        assert.isFalse(SyncStream.awaitingIdentity);
        sinon.assert.notCalled(reconnecting);
      });

      // Every signed-in page load starts with no actor, and following that would drop what the
      // page carried.
      it("only sets the ids on the document's first mount", () => {
        DataLayer.isStoreRestored = false;

        mount("u2");

        assert.equal(LocalDatabase.actorUserId, "u2");
        assert.isNotNull(LocalDatabase.getRow(TASK, "t1"));
        assert.isFalse(SyncStream.awaitingIdentity);
      });
    });
  });

  describe("takeHandshake()", () => {
    const pair = {id: "replica-2", token: "token-2"};

    const answer = (fields = {}) => ({
      actorEntityId: "entity-1",
      actorUserId: "u1",
      identityTag: "1.tag-1",
      replica: pair,
      ...fields,
    });

    let originalLeader, originalName, originalTakingLead, originalTracker;
    let persisting, posting;

    beforeEach(() => {
      originalLeader = Tabs.leader;
      originalName = Tabs.name;
      originalTakingLead = Tabs.takingLead;

      originalTracker = {
        documentPeriod: IdentityTracker.documentPeriod,
        period: IdentityTracker.period,
        periods: IdentityTracker.periods,
        tag: IdentityTracker.tag,
      };

      Replica.reset();
      IdentityTracker.init("1.tag-1");

      LocalDatabase.actorUserId = "u1";
      Replica.owner = "u1";
      SyncStream.followedTag = "1.tag-1";

      Tabs.leader = true;
      Tabs.name = null;
      Tabs.takingLead = false;

      persisting = sinon.stub(Durability, "persistReplica");
      posting = sinon.stub(Tabs, "postState");
    });

    afterEach(() => {
      Object.assign(IdentityTracker, originalTracker);

      Replica.reset();

      LocalDatabase.actorUserId = null;
      SyncStream.awaitingIdentity = false;
      SyncStream.awaitingPair = false;
      SyncStream.followedTag = null;
      SyncStream.laggingCookie = false;

      Tabs.leader = originalLeader;
      Tabs.name = originalName;
      Tabs.takingLead = originalTakingLead;
    });

    it("opens the stream for the identity the tab follows", () => {
      const following = sinon.stub(DataLayer, "followIdentity");

      assert.isTrue(DataLayer.takeHandshake(answer()));
      assert.isFalse(SyncStream.laggingCookie);
      sinon.assert.notCalled(following);
    });

    it("isn't held to an identity by a server that names none", () => {
      SyncStream.laggingCookie = true;

      assert.isTrue(DataLayer.takeHandshake(answer({identityTag: undefined})));
      assert.isFalse(SyncStream.laggingCookie);
      assert.deepStrictEqual(Replica.current(), pair);
    });

    // A login made outside Hologram announces nothing, and a stream opened after the announcement
    // never hears it. The stream about to open replaces the one that held any sync session.
    it("follows an identity the tab missed", () => {
      const following = sinon
        .stub(DataLayer, "followIdentity")
        .callsFake(({identityTag}) => {
          SyncStream.followedTag = identityTag;
        });

      const opens = DataLayer.takeHandshake(
        answer({
          actorEntityId: "entity-2",
          actorUserId: "u2",
          identityTag: "2.tag-2",
        }),
      );

      assert.isTrue(opens);
      assert.isFalse(SyncStream.laggingCookie);

      sinon.assert.calledOnceWithExactly(
        following,
        {actorEntityId: "entity-2", actorUserId: "u2", identityTag: "2.tag-2"},
        {heldSync: false},
      );
    });

    describe("on a cookie behind the identity the tab follows", () => {
      let reconnecting, settling;

      beforeEach(() => {
        IdentityTracker.init("2.tag-2");
        SyncStream.followedTag = "2.tag-2";

        reconnecting = sinon.stub(Sse, "reconnect");
        settling = sinon.stub(Client, "settleIdentity").resolves();
      });

      const takeBehind = () =>
        DataLayer.takeHandshake(
          answer({actorUserId: "u0", identityTag: "1.tag-1"}),
        );

      it("opens no stream", () => {
        assert.isFalse(takeBehind());
      });

      it("holds writes, which the server would take for the previous user's", () => {
        takeBehind();

        assert.isTrue(SyncStream.laggingCookie);
        assert.isTrue(SyncStream.holdsWrites());
      });

      it("opens a new stream once the server has said who is signed in", async () => {
        takeBehind();

        sinon.assert.calledOnce(settling);

        await settling.firstCall.returnValue;
        await Promise.resolve();

        sinon.assert.calledOnce(reconnecting);
      });

      it("keeps the user it follows", () => {
        takeBehind();

        assert.equal(LocalDatabase.actorUserId, "u1");
        assert.equal(SyncStream.followedTag, "2.tag-2");
      });

      // Minted for the previous user.
      it("takes no pair from it", () => {
        takeBehind();

        assert.isNull(Replica.id);
        assert.isNull(Replica.fresh);
      });

      it("lets writes go once a handshake catches up", () => {
        takeBehind();

        DataLayer.takeHandshake(answer({identityTag: "2.tag-2"}));

        assert.isFalse(SyncStream.laggingCookie);
        assert.isFalse(SyncStream.holdsWrites());
      });
    });

    describe("the pair it hands", () => {
      it("is kept as the fresh one", () => {
        Replica.adopt({id: "replica-1", token: "token-1"});

        DataLayer.takeHandshake(answer());

        assert.deepStrictEqual(Replica.fresh, pair);
        assert.deepStrictEqual(Replica.current(), {
          id: "replica-1",
          token: "token-1",
        });
      });

      it("is taken up by a tab in no group that holds none", () => {
        DataLayer.takeHandshake(answer());

        assert.deepStrictEqual(Replica.current(), pair);
        sinon.assert.notCalled(persisting);
        sinon.assert.notCalled(posting);
      });

      it("ends a wait for a pair", () => {
        SyncStream.awaitingPair = true;

        DataLayer.takeHandshake(answer());

        assert.isFalse(SyncStream.holdsWrites());
      });

      describe("in a group", () => {
        beforeEach(() => {
          Tabs.name = "hologram.1.model.u1";
        });

        it("is written down and handed to the group by a leader that holds none", () => {
          DataLayer.takeHandshake(answer());

          assert.deepStrictEqual(Replica.current(), pair);
          sinon.assert.calledOnceWithExactly(persisting, pair);
          sinon.assert.calledOnce(posting);
        });

        // A leader sends only under a pair it has written down.
        it("isn't taken up by a leader whose store slot is another user's", () => {
          Replica.owner = "u0";

          DataLayer.takeHandshake(answer());

          assert.isNull(Replica.id);
          sinon.assert.notCalled(persisting);
          sinon.assert.notCalled(posting);
        });

        // It takes the group's: two pairs in one group would number one queue twice.
        it("is left alone by a follower", () => {
          Tabs.leader = false;

          DataLayer.takeHandshake(answer());

          assert.isNull(Replica.id);
          assert.deepStrictEqual(Replica.fresh, pair);
          sinon.assert.notCalled(persisting);
        });

        // It reads the store's pair, and its next handshake comes once it has settled.
        it("is left alone by a lead still being settled", () => {
          Tabs.takingLead = true;

          DataLayer.takeHandshake(answer());

          assert.isNull(Replica.id);
          sinon.assert.notCalled(persisting);
        });
      });
    });
  });

  describe("pageCounts() and restoreCounts()", () => {
    const TASK = "MyApp.Task";

    let key, term;

    const answer = () =>
      DataLayer.answerDerivedQuery("MyApp.Tasks", Type.atom("total"), [], term);

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [TASK]: {
            attributes: {id: "uuid", title: "string"},
            relationships: {},
            serverOnly: [],
          },
        },
      };

      Model.reset();
      LocalDatabase.reset();
      DataLayer.restoreCounts(null);
      DataLayer.isStoreRestored = true;
      SyncStream.syncCursor = null;

      term = DataLayer.normalizeQuery(
        ManuallyPortedElixirHologramQueryStage["count/1"](Type.alias(TASK)),
      );

      key = `MyApp.Tasks/total/${QuerySpelling.spell(term)}`;
    });

    afterEach(() => {
      DataLayer.restoreCounts(null);
      DataLayer.isStoreRestored = false;
      LocalDatabase.reset();
      LocalDatabase.identityEndedPeriod = null;
      SyncStream.syncCursor = null;
      delete globalThis.Hologram.sync;
    });

    it("gives the counts the page answered with", () => {
      LocalDatabase.carryCounts({[key]: 42}, {[key]: [TASK]});

      answer();

      assert.deepStrictEqual(DataLayer.pageCounts(), [[key, 42, [TASK]]]);
    });

    it("leaves out a held count the page didn't answer with", () => {
      LocalDatabase.carryCounts({[key]: 42}, {[key]: [TASK]});

      assert.deepStrictEqual(DataLayer.pageCounts(), []);
    });

    it("starts over for the next page's mount data", () => {
      LocalDatabase.carryCounts({[key]: 42}, {[key]: [TASK]});
      answer();

      sinon.stub(Deltas, "apply");
      DataLayer.ingestMountData({actorUserId: null, syncRows: {}});

      assert.deepStrictEqual(DataLayer.pageCounts(), []);
    });

    it("starts over for a page restored from its snapshot", () => {
      LocalDatabase.carryCounts({[key]: 42}, {[key]: [TASK]});
      answer();

      DataLayer.restoreCounts(null);

      assert.deepStrictEqual(DataLayer.pageCounts(), []);
    });

    it("answers with a count restored while the client holds no place", () => {
      DataLayer.restoreCounts([[key, 42, [TASK]]]);

      assert.deepStrictEqual(answer(), Type.integer(42));
    });

    it("gives the counts the page arrived with before its first render", () => {
      sinon.stub(Deltas, "apply");

      DataLayer.ingestMountData({
        actorUserId: null,
        syncCountTypes: {[key]: [TASK]},
        syncCounts: {[key]: 42},
        syncRows: {},
      });

      assert.deepStrictEqual(DataLayer.pageCounts(), [[key, 42, [TASK]]]);
    });

    it("gives the counts a restored page saved before its first render", () => {
      DataLayer.restoreCounts([[key, 42, [TASK]]]);

      assert.deepStrictEqual(DataLayer.pageCounts(), [[key, 42, [TASK]]]);
    });

    it("gives the held counts of a page this document saved", () => {
      LocalDatabase.carryCounts({[key]: 42}, {[key]: [TASK]});

      DataLayer.restoreCounts([[key, 42, [TASK]]]);

      assert.deepStrictEqual(DataLayer.pageCounts(), [[key, 42, [TASK]]]);
    });

    // This document counted for itself since it saved it, so the saved number is behind.
    it("files nothing for a count the client has counted itself", () => {
      LocalDatabase.markTypesSynced([TASK]);
      LocalDatabase.beginRefill();

      DataLayer.restoreCounts([[key, 42, [TASK]]]);

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
    });

    // Held back before the first mount, then saved again under this document's period.
    it("files a saved count this document never held", () => {
      DataLayer.isStoreRestored = false;
      DataLayer.restoreCounts([[key, 42, [TASK]]]);

      const saved = DataLayer.pageCounts();

      DataLayer.isStoreRestored = true;
      DataLayer.restoreCounts(saved);

      assert.deepStrictEqual(LocalDatabase.syncCounts, {[key]: 42});
    });

    it("clears the page's counts for mount data carrying no rows", () => {
      DataLayer.isStoreRestored = false;
      DataLayer.restoreCounts([[key, 42, [TASK]]]);

      DataLayer.ingestMountData({actorUserId: null});

      assert.deepStrictEqual(DataLayer.pageCounts(), []);
    });

    describe("after the stream said somebody else signed in", () => {
      let originalPeriod;

      beforeEach(() => {
        originalPeriod = IdentityTracker.period;
        IdentityTracker.period = "period-1";
        LocalDatabase.reset();
      });

      afterEach(() => {
        IdentityTracker.period = originalPeriod;
      });

      // The tab's tag can still be the previous user's when another tab signed the new one in.
      it("files nothing while the period lasts", () => {
        DataLayer.restoreCounts([[key, 42, [TASK]]]);

        assert.deepStrictEqual(LocalDatabase.syncCounts, {});
      });

      // A page fetched before the change can still mount, and says nothing about who is here now.
      it("files nothing after a page from before the change mounts", () => {
        sinon.stub(Deltas, "apply");

        DataLayer.ingestMountData({
          actorUserId: null,
          identityPeriod: "period-1",
          syncRows: {},
        });

        DataLayer.restoreCounts([[key, 42, [TASK]]]);

        assert.deepStrictEqual(LocalDatabase.syncCounts, {});
      });

      it("files the counts once a response started a new period", () => {
        IdentityTracker.period = "period-2";

        DataLayer.restoreCounts([[key, 42, [TASK]]]);

        assert.deepStrictEqual(LocalDatabase.syncCounts, {[key]: 42});
      });
    });

    describe("before this document has read its store", () => {
      beforeEach(() => {
        DataLayer.isStoreRestored = false;
      });

      // A stored place isn't read back yet, so a null one says nothing.
      it("files nothing", () => {
        DataLayer.restoreCounts([[key, 42, [TASK]]]);

        assert.deepStrictEqual(LocalDatabase.syncCounts, {});
      });

      it("keeps the counts for the page's next save", () => {
        DataLayer.restoreCounts([[key, 42, [TASK]]]);

        assert.deepStrictEqual(DataLayer.pageCounts(), [[key, 42, [TASK]]]);
      });

      it("ends once the store is read", () => {
        sinon.stub(Durability, "restore").returns(null);

        DataLayer.restore();

        assert.isTrue(DataLayer.isStoreRestored);
      });

      it("lets them go at the next page's mount data", () => {
        DataLayer.restoreCounts([[key, 42, [TASK]]]);

        sinon.stub(Deltas, "apply");
        DataLayer.ingestMountData({actorUserId: null, syncRows: {}});

        assert.deepStrictEqual(DataLayer.pageCounts(), []);
      });

      // A Back before the first mount restores them while nothing has read the store yet.
      describe("once the store is read", () => {
        const restoreWith = (resumed) => {
          sinon.stub(Durability, "restore").returns(resumed);
          sinon.stub(Batches, "adopt");
          sinon.stub(Batches, "flush");
          sinon.stub(Batches, "resumeFrom");
          sinon.stub(Tabs, "post");
          sinon.stub(Tabs, "ready");

          DataLayer.restore();
        };

        afterEach(() => {
          SyncStream.syncCursor = null;
        });

        it("files them when the store held no place", () => {
          DataLayer.restoreCounts([[key, 42, [TASK]]]);

          restoreWith({batches: [], cursor: null, seq: 0});

          assert.deepStrictEqual(LocalDatabase.syncCounts, {[key]: 42});
        });

        it("files them where there is no store to read", () => {
          DataLayer.restoreCounts([[key, 42, [TASK]]]);

          restoreWith(null);

          assert.deepStrictEqual(LocalDatabase.syncCounts, {[key]: 42});
        });

        // A place says a fill finished, so a saved number is only older.
        it("files nothing when the store held a place", () => {
          DataLayer.restoreCounts([[key, 42, [TASK]]]);

          restoreWith({batches: [], cursor: "Nzc4LjA", seq: 0});

          assert.deepStrictEqual(LocalDatabase.syncCounts, {});
        });

        it("files nothing in a period that ended with somebody else", () => {
          const originalPeriod = IdentityTracker.period;

          DataLayer.restoreCounts([[key, 42, [TASK]]]);

          IdentityTracker.period = "period-1";
          LocalDatabase.identityEndedPeriod = "period-1";

          try {
            restoreWith({batches: [], cursor: null, seq: 0});

            assert.deepStrictEqual(LocalDatabase.syncCounts, {});
          } finally {
            IdentityTracker.period = originalPeriod;
            LocalDatabase.identityEndedPeriod = null;
          }
        });

        // Filing trims to the cap, and a page's own counts are kept past it.
        it("leaves the page's own counts alone when none wait", () => {
          const trimming = sinon.spy(LocalDatabase, "restoreCountEntries");

          restoreWith({batches: [], cursor: null, seq: 0});

          sinon.assert.notCalled(trimming);
        });

        it("holds them no longer", () => {
          DataLayer.restoreCounts([[key, 42, [TASK]]]);

          restoreWith({batches: [], cursor: "Nzc4LjA", seq: 0});

          assert.deepStrictEqual(DataLayer.pageCounts(), []);
        });
      });
    });

    // A place says a fill finished, so the rows are whole and a saved number is only older.
    it("restores nothing while the client holds a place", () => {
      SyncStream.syncCursor = "Nzc4LjA";

      DataLayer.restoreCounts([[key, 42, [TASK]]]);

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
    });

    it("restores nothing for no entries", () => {
      DataLayer.restoreCounts(null);
      DataLayer.restoreCounts(undefined);

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
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

      // A long text a user keeps editing would otherwise keep every version of itself.
      it("keeps no answer for a query with a very long spelling", () => {
        const refusal = sinon.spy(QueryCheck, "refusal");
        const query = term([["title", "==", "x".repeat(5000)]]);

        DataLayer.queryRefusal(query);
        DataLayer.queryRefusal(query);

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
      SyncStream.servedModelHash = null;
      SyncStream.stopReason = null;
    });

    // Served across models, it goes on working; only its next page loads afresh.
    it("leaves the notice down in a tab a server of another model serves", () => {
      const updating = sinon.stub(ReloadNotice, "update");
      const sync = globalThis.Hologram.sync;
      globalThis.Hologram.sync = {...sync, modelHash: "a3f9c2"};

      try {
        SyncStream.servedModelHash = "b7e1d4";

        DataLayer.rendered();

        sinon.assert.calledOnceWithExactly(updating, false);
      } finally {
        globalThis.Hologram.sync = sync;
      }
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
      DataLayer.isStoreRestored = false;

      adopting = sinon.stub(Batches, "adopt");
      flushing = sinon.stub(Batches, "flush");
      resuming = sinon.stub(Batches, "resumeFrom");
      posting = sinon.stub(Tabs, "post");
      readying = sinon.stub(Tabs, "ready");
    });

    afterEach(() => {
      DataLayer.isStoreRestored = false;
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

    // A tab that moved to another user's group takes up what it read for that group itself.
    it("reads no store on a visit after the first", () => {
      const restoring = sinon
        .stub(Durability, "restore")
        .returns({batches: [], cursor: null, seq: 0});

      DataLayer.restore();
      DataLayer.restore();

      sinon.assert.calledOnce(restoring);
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
      SyncStream.servedModelHash = null;
      SyncStream.stopReason = null;
    });

    // Served, but the next page would be the new build's, over this tab's runtime and store.
    it("is true while a server of another model serves the tab", () => {
      const sync = globalThis.Hologram.sync;
      globalThis.Hologram.sync = {...sync, modelHash: "a3f9c2"};

      try {
        SyncStream.servedModelHash = "b7e1d4";

        assert.isTrue(DataLayer.stopped());
      } finally {
        globalThis.Hologram.sync = sync;
      }
    });

    it("is true once the server stopped serving the tab", () => {
      SyncStream.stopReason = "protocol_version";

      assert.isTrue(DataLayer.stopped());
    });

    it("is false while the server serves it", () => {
      assert.isFalse(DataLayer.stopped());
    });

    it("is false while a server of this bundle's model serves it", () => {
      const sync = globalThis.Hologram.sync;
      globalThis.Hologram.sync = {...sync, modelHash: "a3f9c2"};

      try {
        SyncStream.servedModelHash = "a3f9c2";

        assert.isFalse(DataLayer.stopped());
      } finally {
        globalThis.Hologram.sync = sync;
      }
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
