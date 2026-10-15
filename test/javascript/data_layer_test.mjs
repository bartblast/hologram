"use strict";

import {
  assert,
  contextFixture,
  defineRuntimeGlobals,
  sinon,
} from "./support/helpers.mjs";

import Batches from "../../assets/js/batches.mjs";
import DataLayer from "../../assets/js/data_layer.mjs";
import Deltas from "../../assets/js/deltas.mjs";
import Durability from "../../assets/js/durability.mjs";
import GlobalRegistry from "../../assets/js/global_registry.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import ManuallyPortedElixirHologramAuth from "../../assets/js/elixir/hologram/auth.mjs";
import ManuallyPortedElixirHologramDB from "../../assets/js/elixir/hologram/db.mjs";
import ManuallyPortedElixirHologramEntity from "../../assets/js/elixir/hologram/entity.mjs";
import ManuallyPortedElixirHologramJob from "../../assets/js/elixir/hologram/job.mjs";
import ManuallyPortedElixirHologramQuery from "../../assets/js/elixir/hologram/query.mjs";
import Model from "../../assets/js/model.mjs";
import QueryKernel from "../../assets/js/query_kernel.mjs";
import Replica from "../../assets/js/replica.mjs";
import Sse from "../../assets/js/sse.mjs";
import Tabs from "../../assets/js/tabs.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

describe("DataLayer", () => {
  afterEach(() => {
    sinon.restore();
  });

  describe("answerPropQuery()", () => {
    const TASK = "MyApp.Task";

    const count = ManuallyPortedElixirHologramQuery["count/1"];
    const filter = ManuallyPortedElixirHologramQuery["filter/2"];

    // A builder as transpiled app code: it pipes the ported query stages and returns the plain
    // term, and it arrives here boxed the way any capture does.
    const builder = (arity, build) =>
      Type.anonymousFunction(
        arity,
        [
          {
            params: (_context) =>
              Array.from({length: arity}, (_item, index) =>
                Type.variablePattern(`$${index + 1}`),
              ),
            guards: [],
            body: (bodyContext) =>
              build(
                ...Array.from(
                  {length: arity},
                  (_item, index) => bodyContext.vars[`$${index + 1}`],
                ),
              ),
          },
        ],
        contextFixture(),
      );

    const countCapture = () =>
      builder(1, (done) =>
        count(
          filter(
            Type.alias(TASK),
            Type.list([Type.tuple([Type.atom("done"), done])]),
          ),
        ),
      );

    const notDone = [Type.boolean(false)];

    // The struct type and the title of each boxed task, in the order the result holds them.
    const boxedTasks = (result) =>
      result.data.map((task) => [
        task.data[Type.encodeMapKey(Type.atom("__struct__"))][1],
        task.data[Type.encodeMapKey(Type.atom("title"))][1].text,
      ]);

    const orderBy = ManuallyPortedElixirHologramQuery["order_by/2"];

    const allTasks = () => [
      [Type.alias(TASK), "Buy milk"],
      [Type.alias(TASK), "Call Ann"],
      [Type.alias(TASK), "Draft memo"],
    ];

    const taskRow = (id, title, done) => ({
      done: done,
      id: id,
      title: title,
      title_sort: title.toLowerCase(),
    });

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [TASK]: {
            attributes: {done: "boolean", id: "uuid", title: "string"},
            relationships: {},
            serverOnly: [],
          },
        },
        propParams: {},
      };

      Model.reset();
      LocalDatabase.reset();
      LocalDatabase.actorUserId = null;
      GlobalRegistry.set("connectPageModule", null);

      LocalDatabase.putRow(TASK, taskRow("t1", "Buy milk", false));
      LocalDatabase.putRow(TASK, taskRow("t2", "Call Ann", true));
      LocalDatabase.putRow(TASK, taskRow("t3", "Draft memo", false));
    });

    afterEach(() => {
      LocalDatabase.reset();
      LocalDatabase.actorUserId = null;
      delete globalThis.Hologram.sync;
    });

    it("answers from the local database, boxed for the template", () => {
      const capture = builder(0, () =>
        orderBy(Type.alias(TASK), Type.atom("title")),
      );

      const result = DataLayer.answerPropQuery(
        "MyApp.Listing",
        Type.atom("tasks"),
        [],
        capture,
      );

      assert.deepStrictEqual(boxedTasks(result), allTasks());
    });

    it("counts locally when the page carried nothing for the count", () => {
      const result = DataLayer.answerPropQuery(
        "MyApp.NothingCarried",
        Type.atom("count"),
        notDone,
        countCapture(),
      );

      assert.deepStrictEqual(result, Type.integer(2));
    });

    it("answers with the carried count before the marker arrives", () => {
      LocalDatabase.syncCounts = {"MyApp.Carried/count/false": 42};

      const result = DataLayer.answerPropQuery(
        "MyApp.Carried",
        Type.atom("count"),
        notDone,
        countCapture(),
      );

      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("counts locally once the whole pot is complete", () => {
      LocalDatabase.syncCounts = {"MyApp.Complete/count/false": 42};
      LocalDatabase.markSynced("all");

      const result = DataLayer.answerPropQuery(
        "MyApp.Complete",
        Type.atom("count"),
        notDone,
        countCapture(),
      );

      assert.deepStrictEqual(result, Type.integer(2));
    });

    // The page scope covers the page this client connected on, and nothing else - a component on
    // any other page is only promised its rows at "all".
    it("counts locally at the page marker on the page it connected with", () => {
      GlobalRegistry.set("connectPageModule", "MyApp.ConnectPage");
      LocalDatabase.syncCounts = {"MyApp.ConnectPage/count/false": 42};
      LocalDatabase.markSynced("page");

      const result = DataLayer.answerPropQuery(
        "MyApp.ConnectPage",
        Type.atom("count"),
        notDone,
        countCapture(),
      );

      assert.deepStrictEqual(result, Type.integer(2));
    });

    it("keeps carrying at the page marker for a page reached since", () => {
      GlobalRegistry.set("connectPageModule", "MyApp.SomeOtherPage");
      LocalDatabase.syncCounts = {"MyApp.NavigatedTo/count/false": 42};
      LocalDatabase.markSynced("page");

      const result = DataLayer.answerPropQuery(
        "MyApp.NavigatedTo",
        Type.atom("count"),
        notDone,
        countCapture(),
      );

      assert.deepStrictEqual(result, Type.integer(42));
    });

    // Two instances of one component answer two counts, and the arguments their builders were
    // called with are what tell them apart.
    it("reads the count of the arguments the builder was called with", () => {
      LocalDatabase.syncCounts = {
        "MyApp.TwoInstances/count/false": 42,
        "MyApp.TwoInstances/count/true": 7,
      };

      const result = DataLayer.answerPropQuery(
        "MyApp.TwoInstances",
        Type.atom("count"),
        [Type.boolean(true)],
        countCapture(),
      );

      assert.deepStrictEqual(result, Type.integer(7));
    });

    // Two arguments are two values, not their concatenation: 1 and 23 must not read the key
    // 12 and 3 wrote.
    it("separates the arguments a multi-argument builder was called with", () => {
      const capture = builder(2, (_from, _to) => count(Type.alias(TASK)));

      LocalDatabase.syncCounts = {
        "MyApp.TwoArgs/count/1,23": 42,
        "MyApp.TwoArgs/count/123": 7,
      };

      const result = DataLayer.answerPropQuery(
        "MyApp.TwoArgs",
        Type.atom("count"),
        [Type.integer(1), Type.integer(23)],
        capture,
      );

      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("leaves a query that does not count alone", () => {
      const capture = builder(0, () =>
        orderBy(Type.alias(TASK), Type.atom("title")),
      );

      LocalDatabase.syncCounts = {"MyApp.NotCounting/tasks/": 42};

      const result = DataLayer.answerPropQuery(
        "MyApp.NotCounting",
        Type.atom("tasks"),
        [],
        capture,
      );

      assert.deepStrictEqual(boxedTasks(result), allTasks());
    });

    it("runs the query as the acting user", () => {
      const running = sinon.spy(QueryKernel, "run");

      LocalDatabase.actorUserId = "u1";

      DataLayer.answerPropQuery(
        "MyApp.Listing",
        Type.atom("tasks"),
        [],
        builder(0, () => Type.alias(TASK)),
      );

      assert.deepStrictEqual(running.firstCall.args[1], {actorUserId: "u1"});
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
        Sse.syncCursor = "Nzc4LjA";
        Tabs.leader = false;
        Tabs.name = "hologram.1.a3f9c2.u1";
      });

      afterEach(() => {
        Durability.inFlight = originals.inFlight;
        Durability.persisted = originals.persisted;
        Durability.storedBatches = originals.storedBatches;
        Replica.reset();
        Sse.syncCursor = null;
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
      "Elixir_Hologram_Query",
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

    it("defines the hand-written Auth, DB, Entity, Job and Query functions as public functions of their modules", () => {
      DataLayer.defineManuallyPortedFunctions();

      assert.deepStrictEqual(
        globalThis.Elixir_Hologram_Auth.__exports__,
        new Set([
          "can?/3",
          "grant_role/2",
          "grant_role/3",
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
        globalThis.Elixir_Hologram_Query.__exports__,
        new Set([
          "add_relationship/3",
          "authorize/2",
          "count/1",
          "decrement/3",
          "delete_relationship/3",
          "filter/2",
          "include/2",
          "include/3",
          "increment/3",
          "limit/2",
          "normalize/1",
          "offset/2",
          "one/1",
          "order_by/2",
          "put_attribute/2",
          "put_attribute/3",
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
        Elixir_Hologram_Query: ManuallyPortedElixirHologramQuery,
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

  describe("openBatch()", () => {
    it("opens the action's batch for its target", () => {
      const opening = sinon.stub(Batches, "open");

      DataLayer.openBatch("my_component");

      sinon.assert.calledOnceWithExactly(opening, "my_component");
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
      Sse.syncCursor = null;
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

      assert.equal(Sse.syncCursor, "Nzc4LjA");

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

      assert.isNull(Sse.syncCursor);
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
