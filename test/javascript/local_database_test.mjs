"use strict";

import {assert, defineRuntimeGlobals, sinon} from "./support/helpers.mjs";

import Batch from "../../assets/js/batch.mjs";
import Clock from "../../assets/js/clock.mjs";
import Deltas from "../../assets/js/deltas.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Model from "../../assets/js/model.mjs";
import Overlay from "../../assets/js/overlay.mjs";

defineRuntimeGlobals();

describe("LocalDatabase", () => {
  beforeEach(() => {
    LocalDatabase.reset();
    Overlay.reset();
  });

  // The overlay is module state and only a reset drops a pushed batch - LocalDatabase.reset() does
  // not touch it - so a suite that leaves one behind folds its own pending writes into whatever
  // reads next. Only the LAST test to push is exposed, which is what makes this a trap rather than
  // a bug: the ordering decides, not the code.
  afterEach(() => {
    Overlay.reset();
  });

  // A delete is the one write that folds without asking the model anything, which is what makes it
  // the cheapest way to prove a getter goes through the overlay at all. What the fold ANSWERS is
  // Overlay's own suite's business - these three say only that the reads route and the base reads
  // do not.
  //
  // The rows they file carry NO revisions, which is what leaves this stamp of 1 free to be any
  // number: a delete stands against a row holding nothing that could have moved. Give one of them
  // a `$revisions` and the delete starts being weighed against it.
  const pendingDelete = (type, id) => {
    const batch = new Batch("cid");

    batch.append({id, op: "delete", stamp: 1, type});
    Overlay.push(batch);
  };

  describe("getRow() and baseRow()", () => {
    it("reads a pending write, where the base read does not", () => {
      const row = {id: "t1", title: "Draft copy"};

      LocalDatabase.putRow("MyApp.Task", row);
      pendingDelete("MyApp.Task", "t1");

      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t1"));
      assert.strictEqual(LocalDatabase.baseRow("MyApp.Task", "t1"), row);
    });
  });

  describe("getTable() and baseTable()", () => {
    it("reads a pending write, where the base read does not", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});
      pendingDelete("MyApp.Task", "t1");

      assert.deepEqual(LocalDatabase.getTable("MyApp.Task"), {});
      assert.deepEqual(Object.keys(LocalDatabase.baseTable("MyApp.Task")), [
        "t1",
      ]);
    });
  });

  describe("getTargetIds() and baseTargetIds()", () => {
    it("reads a pending write, where the base read does not", () => {
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");
      pendingDelete("MyApp.Project", "p1");

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(),
      );

      assert.deepEqual(
        LocalDatabase.baseTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(["t1"]),
      );
    });
  });

  // What a frame does to a row a pending write is sitting on. Each of the three modules has its
  // own suite for its own half, and what is true only of them together is that they agree about
  // the revisions: Deltas files the arriving ones into the base, Overlay weighs the pending write
  // against them, and the getter is where the two meet. A frame and a write that disagree are
  // spelled here end to end rather than as two halves nobody puts side by side.
  describe("a frame landing under a pending write", () => {
    const TASK = "MyApp.Task";
    const stamp = 1_756_100_000_123 * 1024;

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [TASK]: {
            attributes: {id: "uuid", title: "string"},
            constraints: {},
            defaults: {},
            enumValues: {},
            frameworkAttributes: [],
            relationships: {},
            serverOnly: [],
          },
        },
      };

      Clock.reset();
      Model.reset();
    });

    // Ingest lifts the clock past every revision it sees, and these carry huge ones - left behind,
    // they would stamp whatever suite reads the clock next.
    afterEach(() => {
      Clock.reset();
    });

    const filed = (revision) =>
      Deltas.apply({
        put_entity: {
          [TASK]: [
            {id: "t1", title: "Draft copy", $revisions: {title: revision}},
          ],
        },
      });

    const patched = (title, revision) =>
      Deltas.apply({
        patch_entity: {
          [TASK]: [{id: "t1", title, $revisions: {title: revision}}],
        },
      });

    const pending = (write) => {
      const batch = new Batch("cid");

      batch.append(write);
      Overlay.push(batch);
    };

    it("reads a newer server value through a pending write to the same column", () => {
      filed(10);
      pending({
        data: {title: "Mine"},
        id: "t1",
        op: "update",
        stamp,
        type: TASK,
      });

      assert.equal(LocalDatabase.getRow(TASK, "t1").title, "Mine");

      patched("Theirs", stamp + 1);

      assert.equal(LocalDatabase.getRow(TASK, "t1").title, "Theirs");
    });

    it("keeps a pending delete's row once a newer edit lands", () => {
      filed(10);
      pending({id: "t1", op: "delete", stamp, type: TASK});

      assert.isNull(LocalDatabase.getRow(TASK, "t1"));

      patched("Theirs", stamp + 1);

      assert.equal(LocalDatabase.getRow(TASK, "t1").title, "Theirs");
    });
  });

  describe("reset()", () => {
    it("leaves the pending writes alone, which are not the server's to take away", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});
      pendingDelete("MyApp.Task", "t1");

      LocalDatabase.reset();

      assert.isTrue(Overlay.names("MyApp.Task", "t1"));
    });
  });

  describe("addFact()", () => {
    it("records a pair", () => {
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(["t1"]),
      );
    });

    it("records a repeated pair once", () => {
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(["t1"]),
      );
    });
  });

  describe("carryCounts()", () => {
    const NOTE = "MyApp.Note";
    const TASK = "MyApp.Task";

    it("files the counts with their types", () => {
      LocalDatabase.carryCounts({"a/count/": 3}, {"a/count/": [TASK]});

      assert.deepStrictEqual(LocalDatabase.syncCounts, {"a/count/": 3});
      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {
        "a/count/": [TASK],
      });
    });

    it("skips a count the client already counts itself", () => {
      LocalDatabase.markTypesSynced([TASK]);

      LocalDatabase.carryCounts({"a/count/": 3}, {"a/count/": [TASK]});

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {});
    });

    it("drops a held count whose types have since been marked", () => {
      LocalDatabase.carryCounts(
        {"a/count/": 3, "b/count/": 4},
        {"a/count/": [TASK], "b/count/": [NOTE]},
      );

      LocalDatabase.markTypesSynced([TASK]);
      LocalDatabase.carryCounts({}, {});

      assert.deepStrictEqual(LocalDatabase.syncCounts, {"b/count/": 4});
      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {
        "b/count/": [NOTE],
      });
    });

    it("holds nothing once everything is marked", () => {
      LocalDatabase.carryCounts({"a/count/": 3}, {});
      LocalDatabase.markAllSynced();

      LocalDatabase.carryCounts({"b/count/": 4}, {"b/count/": [TASK]});

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {});
    });

    it("clears the types held under a key filed again with none", () => {
      LocalDatabase.carryCounts({"a/count/": 3}, {"a/count/": [TASK]});

      LocalDatabase.carryCounts({"a/count/": 4}, {});

      assert.deepStrictEqual(LocalDatabase.syncCounts, {"a/count/": 4});
      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {});
    });

    describe("past the limit", () => {
      const counts = (from, to) =>
        Object.fromEntries(
          Array.from({length: to - from}, (_item, index) => [
            `key/${from + index}/`,
            from + index,
          ]),
        );

      const typesOf = (carried) =>
        Object.fromEntries(Object.keys(carried).map((key) => [key, [TASK]]));

      it("drops the oldest from both maps and keeps the ones just filed", () => {
        const earlier = counts(0, 1000);
        const later = counts(1000, 1002);

        LocalDatabase.carryCounts(earlier, typesOf(earlier));
        LocalDatabase.carryCounts(later, typesOf(later));

        assert.equal(Object.keys(LocalDatabase.syncCounts).length, 1000);
        assert.equal(Object.keys(LocalDatabase.syncCountTypes).length, 1000);

        assert.notProperty(LocalDatabase.syncCounts, "key/0/");
        assert.notProperty(LocalDatabase.syncCounts, "key/1/");
        assert.notProperty(LocalDatabase.syncCountTypes, "key/0/");
        assert.notProperty(LocalDatabase.syncCountTypes, "key/1/");

        assert.equal(LocalDatabase.syncCounts["key/2/"], 2);
        assert.equal(LocalDatabase.syncCounts["key/1001/"], 1001);
      });

      it("keeps every count just filed, however many there are", () => {
        const carried = counts(0, 1001);

        LocalDatabase.carryCounts(carried, typesOf(carried));

        assert.equal(Object.keys(LocalDatabase.syncCounts).length, 1001);
      });

      it("drops the oldest once the keys hold too much text", () => {
        const longKey = (name) => `${name}/${"x".repeat(1_500_000)}`;

        for (const name of ["a", "b", "c"]) {
          LocalDatabase.carryCounts(
            {[longKey(name)]: 1},
            {[longKey(name)]: [TASK]},
          );
        }

        assert.notProperty(LocalDatabase.syncCounts, longKey("a"));
        assert.notProperty(LocalDatabase.syncCountTypes, longKey("a"));
        assert.property(LocalDatabase.syncCounts, longKey("b"));
        assert.property(LocalDatabase.syncCounts, longKey("c"));
      });

      it("keeps a count just filed whose key alone holds too much text", () => {
        const key = `a/${"x".repeat(4_000_001)}`;

        LocalDatabase.carryCounts({[key]: 1}, {[key]: [TASK]});

        assert.property(LocalDatabase.syncCounts, key);
      });

      it("counts a key filed again as the newest", () => {
        const earlier = counts(0, 1000);

        LocalDatabase.carryCounts(earlier, typesOf(earlier));
        LocalDatabase.carryCounts(
          {"key/0/": 0, "key/1000/": 1000},
          {"key/0/": [TASK], "key/1000/": [TASK]},
        );

        assert.equal(LocalDatabase.syncCounts["key/0/"], 0);
        assert.notProperty(LocalDatabase.syncCounts, "key/1/");
      });
    });
  });

  describe("countsLocally()", () => {
    const NOTE = "MyApp.Note";
    const TASK = "MyApp.Task";

    it("answers true once every type the count reads is marked", () => {
      LocalDatabase.syncCountTypes = {"a/count/": [TASK, NOTE]};

      LocalDatabase.markTypesSynced([TASK, NOTE]);

      assert.isTrue(LocalDatabase.countsLocally("a/count/"));
    });

    it("answers false while one of its types is not marked", () => {
      LocalDatabase.syncCountTypes = {"a/count/": [TASK, NOTE]};

      LocalDatabase.markTypesSynced([TASK]);

      assert.isFalse(LocalDatabase.countsLocally("a/count/"));
    });

    it("answers false for a count with no types until everything is marked", () => {
      LocalDatabase.markTypesSynced([TASK]);

      assert.isFalse(LocalDatabase.countsLocally("a/count/"));

      LocalDatabase.markAllSynced();

      assert.isTrue(LocalDatabase.countsLocally("a/count/"));
    });
  });

  describe("countEntries()", () => {
    const TASK = "MyApp.Task";

    it("gives each held count with its number and types", () => {
      LocalDatabase.carryCounts({"a/count/": 3}, {"a/count/": [TASK]});

      assert.deepStrictEqual(LocalDatabase.countEntries(["a/count/"]), [
        ["a/count/", 3, [TASK]],
      ]);
    });

    it("gives null for a count with no types", () => {
      LocalDatabase.carryCounts({"a/count/": 3}, {});

      assert.deepStrictEqual(LocalDatabase.countEntries(["a/count/"]), [
        ["a/count/", 3, null],
      ]);
    });

    it("leaves out a key no count is held under", () => {
      assert.deepStrictEqual(LocalDatabase.countEntries(["a/count/"]), []);
    });

    it("leaves out a count the client now counts itself", () => {
      LocalDatabase.carryCounts({"a/count/": 3}, {"a/count/": [TASK]});
      LocalDatabase.markTypesSynced([TASK]);

      assert.deepStrictEqual(LocalDatabase.countEntries(["a/count/"]), []);
    });

    it("stops before the keys hold too much text for a snapshot", () => {
      const first = `a/${"x".repeat(200_000)}`;
      const second = `b/${"x".repeat(200_000)}`;

      LocalDatabase.carryCounts({[first]: 1, [second]: 2}, {});

      assert.deepStrictEqual(LocalDatabase.countEntries([first, second]), [
        [first, 1, null],
      ]);
    });
  });

  describe("restoreCountEntries()", () => {
    const TASK = "MyApp.Task";

    it("files a count that isn't held", () => {
      LocalDatabase.restoreCountEntries([["a/count/", 3, [TASK]]]);

      assert.deepStrictEqual(LocalDatabase.syncCounts, {"a/count/": 3});
      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {
        "a/count/": [TASK],
      });
    });

    it("files a count saved with no types", () => {
      LocalDatabase.restoreCountEntries([["a/count/", 3, null]]);

      assert.deepStrictEqual(LocalDatabase.syncCounts, {"a/count/": 3});
      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {});
    });

    it("keeps the number held over the one saved", () => {
      LocalDatabase.carryCounts({"a/count/": 9}, {"a/count/": [TASK]});

      LocalDatabase.restoreCountEntries([["a/count/", 3, [TASK]]]);

      assert.deepStrictEqual(LocalDatabase.syncCounts, {"a/count/": 9});
    });

    it("skips a count the client can count itself", () => {
      LocalDatabase.markTypesSynced([TASK]);

      LocalDatabase.restoreCountEntries([["a/count/", 3, [TASK]]]);

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
    });

    // The client counted it for itself since the snapshot was saved, so the saved number is
    // behind, though a refill has the client waiting to count again.
    it("skips a count the client counted itself before a refill", () => {
      LocalDatabase.markTypesSynced([TASK]);
      LocalDatabase.beginRefill();

      LocalDatabase.restoreCountEntries([["a/count/", 3, [TASK]]]);

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
    });

    it("skips a count with no types once everything was marked before a refill", () => {
      LocalDatabase.markAllSynced();
      LocalDatabase.beginRefill();

      LocalDatabase.restoreCountEntries([["a/count/", 3, null]]);

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
    });

    // The server hands out a place only for a whole pot, so a document that resumed from a stored
    // place counts for itself though it may have heard no marker yet.
    it("skips a count not held after a refill that gave up a place", () => {
      LocalDatabase.beginRefill({hadPlace: true});

      LocalDatabase.restoreCountEntries([["a/count/", 3, [TASK]]]);

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
    });

    it("keeps a held count after a refill that gave up a place", () => {
      LocalDatabase.carryCounts({"a/count/": 9}, {"a/count/": [TASK]});
      LocalDatabase.beginRefill({hadPlace: true});

      LocalDatabase.restoreCountEntries([["a/count/", 3, [TASK]]]);

      assert.deepStrictEqual(LocalDatabase.syncCounts, {"a/count/": 9});
    });

    it("files a count after a refill that gave up no place", () => {
      LocalDatabase.beginRefill();

      LocalDatabase.restoreCountEntries([["a/count/", 3, [TASK]]]);

      assert.deepStrictEqual(LocalDatabase.syncCounts, {"a/count/": 3});
    });

    it("files a count again once a change of identity follows a given-up place", () => {
      LocalDatabase.beginRefill({hadPlace: true});
      LocalDatabase.reset();

      LocalDatabase.restoreCountEntries([["a/count/", 3, [TASK]]]);

      assert.deepStrictEqual(LocalDatabase.syncCounts, {"a/count/": 3});
    });

    it("files a count again after a change of identity", () => {
      LocalDatabase.markTypesSynced([TASK]);
      LocalDatabase.reset();

      LocalDatabase.restoreCountEntries([["a/count/", 3, [TASK]]]);

      assert.deepStrictEqual(LocalDatabase.syncCounts, {"a/count/": 3});
    });

    it("keeps the restored page's counts past the limit, a held one included", () => {
      const held = Object.fromEntries(
        Array.from({length: 1000}, (_item, index) => [`key/${index}/`, index]),
      );

      LocalDatabase.carryCounts(held, {});

      LocalDatabase.restoreCountEntries([
        ["key/0/", 99, null],
        ["new/count/", 3, null],
      ]);

      assert.equal(LocalDatabase.syncCounts["key/0/"], 0);
      assert.equal(LocalDatabase.syncCounts["new/count/"], 3);
      assert.notProperty(LocalDatabase.syncCounts, "key/1/");
      assert.equal(Object.keys(LocalDatabase.syncCounts).length, 1000);
    });
  });

  describe("dropCounts()", () => {
    it("empties the counts and their types", () => {
      LocalDatabase.syncCounts = {"a/count/": 3};
      LocalDatabase.syncCountTypes = {"a/count/": ["MyApp.Task"]};

      LocalDatabase.dropCounts();

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {});
    });
  });

  describe("beginRefill()", () => {
    const PROJECT = "MyApp.Project";
    const TASK = "MyApp.Task";

    it("drops the completeness marks and the counts the client counted itself", () => {
      LocalDatabase.syncCounts = {"MyApp.Component/todos/": 3};
      LocalDatabase.syncCountTypes = {"MyApp.Component/todos/": [TASK]};
      LocalDatabase.markTypesSynced([TASK]);
      LocalDatabase.markAllSynced();

      LocalDatabase.beginRefill();

      assert.deepStrictEqual(LocalDatabase.syncCounts, {});
      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {});
      assert.isFalse(LocalDatabase.isAllSynced());
      assert.isFalse(LocalDatabase.isTypeSynced(TASK));
    });

    it("keeps a count the client can't count yet", () => {
      LocalDatabase.syncCounts = {"MyApp.Component/todos/": 3};
      LocalDatabase.syncCountTypes = {"MyApp.Component/todos/": [TASK]};

      LocalDatabase.beginRefill();

      assert.deepStrictEqual(LocalDatabase.syncCounts, {
        "MyApp.Component/todos/": 3,
      });

      assert.deepStrictEqual(LocalDatabase.syncCountTypes, {
        "MyApp.Component/todos/": [TASK],
      });
    });

    it("keeps a count with no types while not everything is marked", () => {
      LocalDatabase.syncCounts = {"MyApp.Component/todos/": 3};
      LocalDatabase.markTypesSynced([TASK]);

      LocalDatabase.beginRefill();

      assert.deepStrictEqual(LocalDatabase.syncCounts, {
        "MyApp.Component/todos/": 3,
      });
    });

    it("keeps a count only one of whose types is marked", () => {
      LocalDatabase.syncCounts = {"MyApp.Component/todos/": 3};
      LocalDatabase.syncCountTypes = {
        "MyApp.Component/todos/": [PROJECT, TASK],
      };
      LocalDatabase.markTypesSynced([TASK]);

      LocalDatabase.beginRefill();

      assert.deepStrictEqual(LocalDatabase.syncCounts, {
        "MyApp.Component/todos/": 3,
      });
    });

    it("lets a kept count go only at the marker of the last type it reads", () => {
      const key = "MyApp.Component/todos/";

      LocalDatabase.syncCounts = {[key]: 3};
      LocalDatabase.syncCountTypes = {[key]: [PROJECT, TASK]};

      LocalDatabase.beginRefill();

      LocalDatabase.markTypesSynced([PROJECT]);
      assert.isFalse(LocalDatabase.countsLocally(key));

      LocalDatabase.markTypesSynced([TASK]);
      assert.isTrue(LocalDatabase.countsLocally(key));
    });

    // The client has been counting it, so the number it was carried with is behind by now.
    it("doesn't bring back a count the client was counting itself", () => {
      LocalDatabase.syncCounts = {"MyApp.Component/todos/": 3};
      LocalDatabase.syncCountTypes = {"MyApp.Component/todos/": [TASK]};
      LocalDatabase.markTypesSynced([TASK]);

      LocalDatabase.beginRefill();

      assert.isUndefined(LocalDatabase.syncCounts["MyApp.Component/todos/"]);
      assert.isFalse(LocalDatabase.countsLocally("MyApp.Component/todos/"));
    });

    // The whole point of marking rather than dropping: the screen goes on showing what it showed,
    // and an action that reads or writes one of these rows finds it there.
    it("keeps the rows and their relationship facts", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "held before the resync"});
      LocalDatabase.addFact(PROJECT, "tasks", "p1", "t1");

      LocalDatabase.beginRefill();

      assert.deepStrictEqual(LocalDatabase.getRow(TASK, "t1"), {
        id: "t1",
        title: "held before the resync",
      });

      assert.deepEqual(
        LocalDatabase.getTargetIds(PROJECT, "tasks", "p1"),
        new Set(["t1"]),
      );
    });

    // The other half of the design, stated end to end: the fill delivers what this client may
    // still see, and the marker ending it takes away the rest.
    it("lets the marker sweep what the fill did not confirm", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "delivered again"});
      LocalDatabase.putRow(TASK, {id: "t2", title: "no longer sent"});

      LocalDatabase.beginRefill();
      LocalDatabase.unmarkCarried(TASK, "t1");
      LocalDatabase.markAllSynced();

      assert.deepStrictEqual(LocalDatabase.getRow(TASK, "t1"), {
        id: "t1",
        title: "delivered again",
      });

      assert.isNull(LocalDatabase.getRow(TASK, "t2"));
    });

    it("marks a row already carried once", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "carried by the page"});
      LocalDatabase.markCarried(TASK, "t1");

      LocalDatabase.beginRefill();

      assert.deepStrictEqual(LocalDatabase.carriedEntries(), [[TASK, "t1"]]);
    });

    it("marks every held row as awaiting the fill", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "a task"});
      LocalDatabase.putRow(TASK, {id: "t2", title: "another task"});
      LocalDatabase.putRow(PROJECT, {id: "p1", name: "a project"});

      LocalDatabase.beginRefill();

      assert.sameDeepMembers(LocalDatabase.carriedEntries(), [
        [PROJECT, "p1"],
        [TASK, "t1"],
        [TASK, "t2"],
      ]);
    });
  });

  describe("deleteFact()", () => {
    it("removes a pair, keeping the source's other pairs", () => {
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t2");

      LocalDatabase.deleteFact("MyApp.Project", "tasks", "p1", "t1");

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(["t2"]),
      );
    });

    it("does nothing for a pair never recorded", () => {
      LocalDatabase.deleteFact("MyApp.Project", "tasks", "p1", "t1");

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(),
      );
    });
  });

  describe("deleteRow()", () => {
    it("removes the row", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});

      LocalDatabase.deleteRow("MyApp.Task", "t1");

      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t1"));
    });

    it("removes the row's relationship facts with it", () => {
      LocalDatabase.putRow("MyApp.Project", {id: "p1", name: "Website"});
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");

      LocalDatabase.deleteRow("MyApp.Project", "p1");

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(),
      );
    });

    it("keeps other rows and their facts", () => {
      LocalDatabase.putRow("MyApp.Project", {id: "p1", name: "Website"});
      LocalDatabase.putRow("MyApp.Project", {id: "p2", name: "Launch"});
      LocalDatabase.addFact("MyApp.Project", "tasks", "p2", "t2");

      LocalDatabase.deleteRow("MyApp.Project", "p1");

      assert.deepEqual(LocalDatabase.getRow("MyApp.Project", "p2"), {
        id: "p2",
        name: "Launch",
      });

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p2"),
        new Set(["t2"]),
      );
    });

    it("does nothing for a row never held", () => {
      LocalDatabase.deleteRow("MyApp.Task", "t1");

      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t1"));
    });
  });

  describe("getRow()", () => {
    it("returns the held row", () => {
      const row = {id: "t1", title: "Draft copy"};
      LocalDatabase.putRow("MyApp.Task", row);

      assert.equal(LocalDatabase.getRow("MyApp.Task", "t1"), row);
    });

    it("returns null for an id not held", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});

      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t9"));
    });

    it("returns null for a type never filed", () => {
      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t1"));
    });
  });

  describe("getTable()", () => {
    it("returns the type's rows keyed by id", () => {
      const first = {id: "t1", title: "Draft copy"};
      const second = {id: "t2", title: "Ship it"};

      LocalDatabase.putRow("MyApp.Task", first);
      LocalDatabase.putRow("MyApp.Task", second);

      assert.deepEqual(LocalDatabase.getTable("MyApp.Task"), {
        t1: first,
        t2: second,
      });
    });

    it("returns an empty table for a type never filed", () => {
      assert.deepEqual(LocalDatabase.getTable("MyApp.Task"), {});
    });
  });

  describe("getTargetIds()", () => {
    it("returns the source's pair targets", () => {
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t2");

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(["t1", "t2"]),
      );
    });

    it("returns an empty set for a source never recorded", () => {
      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(),
      );
    });
  });

  describe("hasFacts()", () => {
    it("answers true for a set that was filed and is empty", () => {
      LocalDatabase.replaceFacts("MyApp.Task", "tags", "t1", []);

      assert.isTrue(LocalDatabase.hasFacts("MyApp.Task", "tags", "t1"));
    });

    it("answers false for a triple nothing was ever filed under", () => {
      assert.isFalse(LocalDatabase.hasFacts("MyApp.Task", "tags", "t1"));
    });
  });

  describe("heldOrNamedIds()", () => {
    const PROJECT = "MyApp.Project";
    const TASK = "MyApp.Task";

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [PROJECT]: {
            attributes: {id: "uuid"},
            relationships: {tasks: {toMany: true, type: TASK}},
            serverOnly: [],
          },
          [TASK]: {
            attributes: {id: "uuid"},
            inverses: {
              owners: {
                forward: "tasks",
                reference: false,
                sort: [],
                toMany: true,
                type: PROJECT,
              },
            },
            relationships: {},
            serverOnly: [],
          },
        },
      };

      Model.reset();
    });

    afterEach(() => {
      delete globalThis.Hologram.sync;
      Model.reset();
    });

    it("answers the ids of the rows it holds", () => {
      LocalDatabase.putRow(TASK, {id: "t1"});

      assert.deepEqual(LocalDatabase.heldOrNamedIds(TASK), new Set(["t1"]));
    });

    it("answers an id a to-many of a held row names", () => {
      LocalDatabase.putRow(PROJECT, {id: "p1"});
      LocalDatabase.addFact(PROJECT, "tasks", "p1", "t1");

      assert.deepEqual(LocalDatabase.heldOrNamedIds(TASK), new Set(["t1"]));
    });

    it("answers an id an inverse of a held row names", () => {
      LocalDatabase.putRow(TASK, {id: "t1"});
      LocalDatabase.addFact(TASK, "owners", "t1", "p1");

      assert.deepEqual(LocalDatabase.heldOrNamedIds(PROJECT), new Set(["p1"]));
    });

    it("leaves out an id named only under a row it doesn't hold", () => {
      LocalDatabase.addFact(PROJECT, "tasks", "p1", "t1");

      assert.deepEqual(LocalDatabase.heldOrNamedIds(TASK), new Set());
    });
  });

  describe("isAllSynced()", () => {
    it("answers false before the marker arrived", () => {
      assert.isFalse(LocalDatabase.isAllSynced());
    });

    it("answers true once everything is marked", () => {
      LocalDatabase.markAllSynced();

      assert.isTrue(LocalDatabase.isAllSynced());
    });

    it("answers false while only types are marked", () => {
      LocalDatabase.markTypesSynced(["MyApp.Task"]);

      assert.isFalse(LocalDatabase.isAllSynced());
    });
  });

  describe("isTypeSynced()", () => {
    it("answers false before the type's marker arrived", () => {
      assert.isFalse(LocalDatabase.isTypeSynced("MyApp.Task"));
    });

    it("answers true once the type is marked", () => {
      LocalDatabase.markTypesSynced(["MyApp.Task"]);

      assert.isTrue(LocalDatabase.isTypeSynced("MyApp.Task"));
    });

    it("marks each type on its own", () => {
      LocalDatabase.markTypesSynced(["MyApp.Task"]);

      assert.isFalse(LocalDatabase.isTypeSynced("MyApp.Project"));
    });

    // Everything complete is every type complete, the ones no marker named included.
    it("answers true for any type once everything is marked", () => {
      LocalDatabase.markAllSynced();

      assert.isTrue(LocalDatabase.isTypeSynced("MyApp.Task"));
    });
  });

  describe("markAllSynced()", () => {
    describe("a pair naming a swept row", () => {
      const PROJECT = "MyApp.Project";
      const TASK = "MyApp.Task";

      beforeEach(() => {
        globalThis.Hologram.sync = {
          model: {
            [PROJECT]: {
              attributes: {id: "uuid"},
              relationships: {tasks: {toMany: true, type: TASK}},
              serverOnly: [],
            },
            [TASK]: {
              attributes: {id: "uuid"},
              relationships: {},
              serverOnly: [],
            },
          },
        };

        Model.reset();

        LocalDatabase.putRow(PROJECT, {id: "p1"});
        LocalDatabase.putRow(TASK, {id: "t1"});
        LocalDatabase.putRow(TASK, {id: "t2"});
        LocalDatabase.replaceFacts(PROJECT, "tasks", "p1", ["t1", "t2"]);
        LocalDatabase.markCarried(TASK, "t1");
      });

      afterEach(() => {
        delete globalThis.Hologram.sync;
        Model.reset();
      });

      it("takes the pair and leaves one naming a row still held", () => {
        LocalDatabase.markAllSynced();

        assert.deepEqual(
          LocalDatabase.baseTargetIds(PROJECT, "tasks", "p1"),
          new Set(["t2"]),
        );
      });

      // This marker also ends a catch-up, whose store still holds the pair.
      it("queues the pair to be taken out of the stored set", () => {
        LocalDatabase.markAllSynced();

        assert.deepEqual(LocalDatabase.takeStoredFactRemovals(), [
          {id: "p1", relationship: "tasks", targetIds: ["t1"], type: PROJECT},
        ]);
      });
    });

    // What a page still carries when the whole pot declares itself complete was never this
    // client's to hold - a grant revoked between the render and the connect leaves exactly that.
    it("drops a carried row the fill never delivered", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});
      LocalDatabase.markCarried("MyApp.Task", "t1");

      LocalDatabase.markAllSynced();

      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t1"));
      assert.deepEqual(LocalDatabase.carriedEntries(), []);
    });

    it("keeps a carried row the fill delivered", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});
      LocalDatabase.markCarried("MyApp.Task", "t1");
      LocalDatabase.unmarkCarried("MyApp.Task", "t1");

      LocalDatabase.markAllSynced();

      assert.deepEqual(LocalDatabase.getRow("MyApp.Task", "t1"), {
        id: "t1",
        title: "Draft copy",
      });
    });

    it("sweeps nothing when told again", () => {
      LocalDatabase.markAllSynced();

      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "carried since"});
      LocalDatabase.markCarried("MyApp.Task", "t1");

      LocalDatabase.markAllSynced();

      assert.isNotNull(LocalDatabase.getRow("MyApp.Task", "t1"));
    });

    it("keeps a row no page carried", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});

      LocalDatabase.markAllSynced();

      assert.deepEqual(LocalDatabase.getRow("MyApp.Task", "t1"), {
        id: "t1",
        title: "Draft copy",
      });
    });

    // A swept row takes its relationship facts with it, the way any row leaving the pot does.
    it("takes the swept row's relationship facts with it", () => {
      LocalDatabase.putRow("MyApp.Project", {id: "p1", name: "Board"});
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");
      LocalDatabase.markCarried("MyApp.Project", "p1");

      LocalDatabase.markAllSynced();

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(),
      );
    });
  });

  describe("markTypesSynced()", () => {
    // The fill sends every row of a type the client may see before the type's marker, so a row of
    // it still held only because a page carried it, or from before a refill, is not the client's.
    it("drops a carried row of a marked type the fill never delivered", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});
      LocalDatabase.markCarried("MyApp.Task", "t1");

      LocalDatabase.markTypesSynced(["MyApp.Task"]);

      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t1"));
      assert.deepEqual(LocalDatabase.carriedEntries(), []);
    });

    it("keeps a carried row of a marked type the fill delivered", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});
      LocalDatabase.markCarried("MyApp.Task", "t1");
      LocalDatabase.unmarkCarried("MyApp.Task", "t1");

      LocalDatabase.markTypesSynced(["MyApp.Task"]);

      assert.isNotNull(LocalDatabase.getRow("MyApp.Task", "t1"));
    });

    // A type's marker says nothing about another type's rows, which may still be on their way.
    it("keeps a carried row of a type no marker named", () => {
      LocalDatabase.putRow("MyApp.Project", {id: "p1", name: "Board"});
      LocalDatabase.markCarried("MyApp.Project", "p1");

      LocalDatabase.markTypesSynced(["MyApp.Task"]);

      assert.deepEqual(LocalDatabase.carriedEntries(), [
        ["MyApp.Project", "p1"],
      ]);
      assert.isNotNull(LocalDatabase.getRow("MyApp.Project", "p1"));
    });

    // A mark told again - a tab of the group posting its state on every join - is no new word about
    // a row a page carried since, which the stream has yet to deliver.
    it("sweeps nothing for a type already marked", () => {
      LocalDatabase.markTypesSynced(["MyApp.Task"]);

      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "carried since"});
      LocalDatabase.markCarried("MyApp.Task", "t1");

      LocalDatabase.markTypesSynced(["MyApp.Task"]);

      assert.isNotNull(LocalDatabase.getRow("MyApp.Task", "t1"));
    });

    it("sweeps nothing once everything is marked", () => {
      LocalDatabase.markAllSynced();

      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "carried since"});
      LocalDatabase.markCarried("MyApp.Task", "t1");

      LocalDatabase.markTypesSynced(["MyApp.Task"]);

      assert.isNotNull(LocalDatabase.getRow("MyApp.Task", "t1"));
    });

    it("marks every type it is given", () => {
      LocalDatabase.markTypesSynced(["MyApp.Project", "MyApp.Task"]);

      assert.isTrue(LocalDatabase.isTypeSynced("MyApp.Project"));
      assert.isTrue(LocalDatabase.isTypeSynced("MyApp.Task"));
    });
  });

  describe("a row an answer filed during a fill", () => {
    const TAG = "MyApp.Tag";
    const TASK = "MyApp.Task";

    const promoted = (seq, type = TASK, id = "t1") => {
      LocalDatabase.putRow(type, {id, title: "created here"});
      LocalDatabase.markPromoted(type, id, seq);
    };

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [TAG]: {
            attributes: {id: "uuid", name: "string"},
            enumValues: {},
            inverses: {
              tasks: {
                forward: "tags",
                reference: false,
                sort: [],
                toMany: true,
                type: TASK,
              },
            },
            relationships: {},
            serverOnly: [],
          },
          [TASK]: {
            attributes: {id: "uuid", title: "string"},
            enumValues: {},
            inverses: {},
            relationships: {
              tags: {optional: true, toMany: true, type: TAG},
            },
            serverOnly: [],
          },
        },
      };

      Model.reset();
    });

    afterEach(() => {
      delete globalThis.Hologram.sync;

      Model.reset();
    });

    it("carries the row until its type's marker", () => {
      promoted(3);

      assert.deepEqual(LocalDatabase.carriedEntries(), [[TASK, "t1"]]);
      assert.isFalse(LocalDatabase.vouchedRowKeys().has(`${TASK} t1`));
    });

    // The fill read the batch and left the row out, so its user may not read it.
    it("takes the row away at a marker at or above its batch", () => {
      promoted(3);

      LocalDatabase.markTypesSynced([TASK], 3);

      assert.isNull(LocalDatabase.baseRow(TASK, "t1"));
      assert.deepEqual(LocalDatabase.carriedEntries(), []);
    });

    it("keeps a row the fill delivered", () => {
      promoted(3);

      LocalDatabase.unmarkCarried(TASK, "t1");
      LocalDatabase.markTypesSynced([TASK], 3);

      assert.isNotNull(LocalDatabase.baseRow(TASK, "t1"));
    });

    // Committed after the type was read, so its session judges it.
    it("keeps the row at a marker below its batch, and at the marker for everything", () => {
      promoted(4);

      LocalDatabase.markTypesSynced([TASK], 3);

      assert.isNotNull(LocalDatabase.baseRow(TASK, "t1"));
      assert.isFalse(LocalDatabase.vouchedRowKeys().has(`${TASK} t1`));

      LocalDatabase.markAllSynced();

      assert.isNotNull(LocalDatabase.baseRow(TASK, "t1"));
      assert.isTrue(LocalDatabase.vouchedRowKeys().has(`${TASK} t1`));
    });

    it("keeps the row at a marker naming no number", () => {
      promoted(3);

      LocalDatabase.markTypesSynced([TASK], null);

      assert.isNotNull(LocalDatabase.baseRow(TASK, "t1"));

      LocalDatabase.markAllSynced();

      assert.isNotNull(LocalDatabase.baseRow(TASK, "t1"));
      assert.deepEqual(LocalDatabase.carriedEntries(), []);
    });

    it("keeps the row at a marker of an older node, which names no number at all", () => {
      promoted(3);

      LocalDatabase.markTypesSynced([TASK], undefined);

      assert.isNotNull(LocalDatabase.baseRow(TASK, "t1"));
    });

    it("leaves the row carried at another type's marker", () => {
      promoted(3);

      LocalDatabase.markTypesSynced([TAG], 3);

      assert.isNotNull(LocalDatabase.baseRow(TASK, "t1"));
      assert.deepEqual(LocalDatabase.carriedEntries(), [[TASK, "t1"]]);
    });

    // Neither a fill nor a session speaks for a type sync doesn't send.
    it("keeps a row of a type no marker named at the marker for everything", () => {
      promoted(3);

      LocalDatabase.markAllSynced();

      assert.isNotNull(LocalDatabase.baseRow(TASK, "t1"));
      assert.deepEqual(LocalDatabase.carriedEntries(), []);
    });

    it("takes the row out of the sets naming it, and answers the holders", () => {
      promoted(3, TAG, "g1");

      LocalDatabase.putRow(TASK, {id: "t1", title: "held"});
      LocalDatabase.replaceFacts(TASK, "tags", "t1", ["g1", "g2"]);

      const written = LocalDatabase.markTypesSynced([TAG], 3);

      assert.deepEqual(
        Array.from(LocalDatabase.baseTargetIds(TASK, "tags", "t1")),
        ["g2"],
      );

      assert.deepEqual(Array.from(written), [`${TASK} t1`]);
    });

    // A row a page carried is never stored, so its set has nothing to be written down.
    it("doesn't answer a holder a page carried", () => {
      promoted(3, TAG, "g1");

      LocalDatabase.putRow(TASK, {id: "t1", title: "carried"});
      LocalDatabase.markCarried(TASK, "t1");
      LocalDatabase.replaceFacts(TASK, "tags", "t1", ["g1"]);

      const written = LocalDatabase.markTypesSynced([TAG], 3);

      assert.equal(LocalDatabase.baseTargetIds(TASK, "tags", "t1").size, 0);
      assert.equal(written.size, 0);
    });

    // The holder is kept for its session to judge, so no stream has vouched for it yet.
    it("doesn't answer a holder still waiting for its session", () => {
      promoted(4, TASK, "h1");
      promoted(3, TAG, "g1");

      LocalDatabase.replaceFacts(TASK, "tags", "h1", ["g1"]);
      LocalDatabase.markTypesSynced([TASK], 2);

      const written = LocalDatabase.markTypesSynced([TAG], 4);

      assert.isNull(LocalDatabase.baseRow(TAG, "g1"));
      assert.equal(LocalDatabase.baseTargetIds(TASK, "tags", "h1").size, 0);
      assert.equal(written.size, 0);
    });

    // A create over a row a page carried is never recorded, and the sweep still takes the row.
    it("takes a swept page-carried row out of the sets naming it", () => {
      LocalDatabase.putRow(TAG, {id: "g1", name: "carried"});
      LocalDatabase.markCarried(TAG, "g1");
      LocalDatabase.putRow(TASK, {id: "t1", title: "held"});
      LocalDatabase.replaceFacts(TASK, "tags", "t1", ["g1"]);

      const written = LocalDatabase.markTypesSynced([TAG], 3);

      assert.equal(LocalDatabase.baseTargetIds(TASK, "tags", "t1").size, 0);
      assert.deepEqual(Array.from(written), [`${TASK} t1`]);
    });

    it("leaves the sets naming a row it keeps", () => {
      promoted(4, TAG, "g1");

      LocalDatabase.putRow(TASK, {id: "t1", title: "held"});
      LocalDatabase.replaceFacts(TASK, "tags", "t1", ["g1"]);

      const written = LocalDatabase.markTypesSynced([TAG], 3);

      assert.isTrue(LocalDatabase.baseTargetIds(TASK, "tags", "t1").has("g1"));
      assert.equal(written.size, 0);
    });

    // An answer landing before a greeting committed before that fill, so every marker covers it,
    // whatever number it was recorded with.
    it("forgets the number at a refill, and the marker takes the row", () => {
      promoted(5);

      LocalDatabase.beginRefill();
      LocalDatabase.markTypesSynced([TASK], 3);

      assert.isNull(LocalDatabase.baseRow(TASK, "t1"));
    });

    it("forgets the number at a reset", () => {
      promoted(5);

      LocalDatabase.reset();

      LocalDatabase.putRow(TASK, {id: "t1", title: "carried"});
      LocalDatabase.markCarried(TASK, "t1");
      LocalDatabase.markTypesSynced([TASK], 3);

      assert.isNull(LocalDatabase.baseRow(TASK, "t1"));
    });
  });

  describe("putRow()", () => {
    it("files the row under its id", () => {
      const row = {id: "t1", title: "Draft copy"};

      LocalDatabase.putRow("MyApp.Task", row);

      assert.equal(LocalDatabase.getRow("MyApp.Task", "t1"), row);
    });

    it("replaces the row already held under the id", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});

      const fresher = {id: "t1", title: "Ship it"};
      LocalDatabase.putRow("MyApp.Task", fresher);

      assert.equal(LocalDatabase.getRow("MyApp.Task", "t1"), fresher);
    });
  });

  describe("records()", () => {
    const TAG = "MyApp.Tag";
    const TASK = "MyApp.Task";

    // The model is read for one thing only - which of a type's relationships and inverses hold
    // facts - so what is baked here is that and the little Model.entry insists on.
    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [TAG]: {
            attributes: {id: "uuid", name: "string"},
            enumValues: {},
            inverses: {
              tasks: {
                forward: "tags",
                reference: false,
                sort: [],
                toMany: true,
                type: TASK,
              },
            },
            relationships: {},
            serverOnly: [],
          },
          [TASK]: {
            attributes: {id: "uuid", title: "string"},
            enumValues: {},
            relationships: {
              project: {optional: false, toMany: false, type: "MyApp.Project"},
              tags: {optional: true, toMany: true, type: TAG},
            },
            serverOnly: [],
          },
        },
      };

      Model.reset();
    });

    afterEach(() => {
      delete globalThis.Hologram.sync;
      Model.reset();
    });

    // The whole record is asserted rather than its facts alone, which is what pins the to-one out:
    // a project lives in the row as a reference field, and naming it here would store it twice.
    it("snapshots a held row with its to-many facts", () => {
      const row = {id: "t1", project_id: "p1", title: "Draft copy"};

      LocalDatabase.putRow(TASK, row);
      LocalDatabase.replaceFacts(TASK, "tags", "t1", ["g1", "g2"]);

      assert.deepStrictEqual(LocalDatabase.records([`${TASK} t1`]), [
        {facts: {tags: ["g1", "g2"]}, id: "t1", row, type: TASK},
      ]);
    });

    it("snapshots a row whose type declares no to-many with empty facts", () => {
      const row = {id: "g1", name: "urgent"};

      LocalDatabase.putRow(TAG, row);

      assert.deepStrictEqual(LocalDatabase.records([`${TAG} g1`]), [
        {facts: {}, id: "g1", row, type: TAG},
      ]);
    });

    it("snapshots the facts of an inverse of a to-many beside the row", () => {
      const row = {id: "g1", name: "urgent"};

      LocalDatabase.putRow(TAG, row);
      LocalDatabase.replaceFacts(TAG, "tasks", "g1", ["t1"]);

      assert.deepStrictEqual(LocalDatabase.records([`${TAG} g1`]), [
        {facts: {tasks: ["t1"]}, id: "g1", row, type: TAG},
      ]);
    });

    // Written down as empty, it would say the server declared the relationship empty - which
    // nobody did - and restoring it would file that assertion. The pair below is the whole claim:
    // a set that WAS filed and is empty is stored, one nobody filed is left out.
    it("leaves out a to-many nothing was filed under", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "Draft copy"});

      assert.deepStrictEqual(
        LocalDatabase.records([`${TASK} t1`])[0].facts,
        {},
      );
    });

    it("stores a filed to-many that is empty", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "Draft copy"});
      LocalDatabase.replaceFacts(TASK, "tags", "t1", []);

      assert.deepStrictEqual(LocalDatabase.records([`${TASK} t1`])[0].facts, {
        tags: [],
      });
    });

    it("answers no row for a key the base does not hold", () => {
      assert.deepStrictEqual(LocalDatabase.records([`${TASK} t1`]), [
        {id: "t1", row: null, type: TASK},
      ]);
    });

    it("keeps the order of the keys given", () => {
      LocalDatabase.putRow(TAG, {id: "g1", name: "urgent"});
      LocalDatabase.putRow(TASK, {id: "t1", title: "Draft copy"});

      const snapshot = LocalDatabase.records([`${TASK} t1`, `${TAG} g1`]);

      assert.deepStrictEqual(
        snapshot.map((record) => record.id),
        ["t1", "g1"],
      );
    });

    // What goes to durable storage is what the SERVER said, never what this client has written and
    // not yet had answered - a pending delete's row is still the server's row until it lands.
    it("reads the base, not the overlay", () => {
      const row = {id: "t1", title: "Draft copy"};

      LocalDatabase.putRow(TASK, row);
      pendingDelete(TASK, "t1");

      assert.isNull(LocalDatabase.getRow(TASK, "t1"));

      assert.deepStrictEqual(LocalDatabase.records([`${TASK} t1`]), [
        {facts: {}, id: "t1", row, type: TASK},
      ]);
    });
  });

  describe("replaceFacts()", () => {
    it("records the whole target set", () => {
      LocalDatabase.replaceFacts("MyApp.Project", "tasks", "p1", ["t1", "t2"]);

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(["t1", "t2"]),
      );
    });

    it("drops pairs the new set no longer holds", () => {
      LocalDatabase.replaceFacts("MyApp.Project", "tasks", "p1", ["t1", "t2"]);

      LocalDatabase.replaceFacts("MyApp.Project", "tasks", "p1", ["t2", "t3"]);

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(["t2", "t3"]),
      );
    });

    it("records an empty set as truly empty", () => {
      LocalDatabase.replaceFacts("MyApp.Project", "tasks", "p1", ["t1"]);

      LocalDatabase.replaceFacts("MyApp.Project", "tasks", "p1", []);

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(),
      );
    });
  });

  describe("restore()", () => {
    const TASK = "MyApp.Task";

    const record = (id, attributes = {}, facts = {}) => ({
      facts,
      id,
      row: {id, ...attributes},
      type: TASK,
    });

    it("files a row the base does not hold, with its facts", () => {
      LocalDatabase.restore([
        record("t1", {title: "Draft copy"}, {tags: ["g1", "g2"]}),
      ]);

      assert.deepStrictEqual(LocalDatabase.baseRow(TASK, "t1"), {
        id: "t1",
        title: "Draft copy",
      });

      assert.deepStrictEqual(
        Array.from(LocalDatabase.baseTargetIds(TASK, "tags", "t1")),
        ["g1", "g2"],
      );
    });

    // The page's row is the fresher of the two, so the stored one adds nothing to it - the same
    // object comes back, not a copy of the stored values.
    it("leaves a held row's values alone", () => {
      const carried = {id: "t1", title: "Ship it"};

      LocalDatabase.putRow(TASK, carried);
      LocalDatabase.restore([record("t1", {title: "Draft copy"})]);

      assert.strictEqual(LocalDatabase.baseRow(TASK, "t1"), carried);
    });

    it("unmarks a held row as carried", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "Ship it"});
      LocalDatabase.markCarried(TASK, "t1");

      LocalDatabase.restore([record("t1", {title: "Draft copy"})]);

      assert.deepStrictEqual(LocalDatabase.carriedEntries(), []);
    });

    it("leaves another row's carried mark alone", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "Ship it"});
      LocalDatabase.putRow(TASK, {id: "t2", title: "Draft copy"});
      LocalDatabase.markCarried(TASK, "t1");

      LocalDatabase.restore([record("t2")]);

      assert.deepStrictEqual(LocalDatabase.carriedEntries(), [[TASK, "t1"]]);
    });

    it("fills a held row's facts for a relationship nothing was filed under", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "Ship it"});

      LocalDatabase.restore([record("t1", {}, {tags: ["g1"]})]);

      assert.deepStrictEqual(
        Array.from(LocalDatabase.baseTargetIds(TASK, "tags", "t1")),
        ["g1"],
      );
    });

    // A page's row states the whole set of every relationship it named, an empty one included -
    // so a filed set is this page's word about the world and outranks the stored one.
    it("leaves a held row's filed facts alone, empty ones included", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "Ship it"});
      LocalDatabase.replaceFacts(TASK, "tags", "t1", []);

      LocalDatabase.restore([record("t1", {}, {tags: ["g1"]})]);

      assert.deepStrictEqual(
        Array.from(LocalDatabase.baseTargetIds(TASK, "tags", "t1")),
        [],
      );
    });

    // The record naming a gone row is passed over and the one behind it is still filed - a skip
    // rather than a stop.
    it("passes over a record whose row is gone", () => {
      LocalDatabase.restore([
        {id: "t1", row: null, type: TASK},
        record("t2", {title: "Draft copy"}),
      ]);

      assert.isNull(LocalDatabase.baseRow(TASK, "t1"));
      assert.isNotNull(LocalDatabase.baseRow(TASK, "t2"));
    });
  });

  describe("syncedState()", () => {
    it("answers nothing complete before any marker has arrived", () => {
      assert.deepStrictEqual(LocalDatabase.syncedState(), {
        all: false,
        types: [],
      });
    });

    it("answers what has been marked so far", () => {
      LocalDatabase.markTypesSynced(["MyApp.Task", "MyApp.Project"]);
      LocalDatabase.markAllSynced();

      const state = LocalDatabase.syncedState();

      assert.isTrue(state.all);
      assert.sameMembers(state.types, ["MyApp.Project", "MyApp.Task"]);
    });
  });

  describe("vouchedRowKeys()", () => {
    const TASK = "MyApp.Task";

    it("answers every base row that no page carried", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "from the stream"});
      LocalDatabase.putRow(TASK, {id: "t2", title: "from the page"});
      LocalDatabase.markCarried(TASK, "t2");

      assert.deepStrictEqual(Array.from(LocalDatabase.vouchedRowKeys()), [
        `${TASK} t1`,
      ]);
    });

    it("answers the rows of every type it holds", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "a task"});
      LocalDatabase.putRow("MyApp.Project", {id: "p1", name: "a project"});

      assert.sameMembers(Array.from(LocalDatabase.vouchedRowKeys()), [
        "MyApp.Project p1",
        `${TASK} t1`,
      ]);
    });

    it("answers a row again once it is unmarked", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "from the page"});
      LocalDatabase.markCarried(TASK, "t1");
      LocalDatabase.unmarkCarried(TASK, "t1");

      assert.deepStrictEqual(Array.from(LocalDatabase.vouchedRowKeys()), [
        `${TASK} t1`,
      ]);
    });

    it("answers nothing for a database holding nothing", () => {
      assert.deepStrictEqual(Array.from(LocalDatabase.vouchedRowKeys()), []);
    });
  });

  describe("carriedEntries()", () => {
    it("returns the rows marked as arrived with a page", () => {
      LocalDatabase.markCarried("MyApp.Task", "t1");
      LocalDatabase.markCarried("MyApp.Project", "p1");

      assert.sameDeepMembers(LocalDatabase.carriedEntries(), [
        ["MyApp.Task", "t1"],
        ["MyApp.Project", "p1"],
      ]);
    });

    it("returns nothing once a row is unmarked", () => {
      LocalDatabase.markCarried("MyApp.Task", "t1");
      LocalDatabase.unmarkCarried("MyApp.Task", "t1");

      assert.deepEqual(LocalDatabase.carriedEntries(), []);
    });

    it("returns a row whose id was unmarked under another type", () => {
      LocalDatabase.markCarried("MyApp.Task", "t1");
      LocalDatabase.unmarkCarried("MyApp.Project", "t1");

      assert.deepEqual(LocalDatabase.carriedEntries(), [["MyApp.Task", "t1"]]);
    });
  });

  describe("the final point", () => {
    const TASK = "MyApp.Task";

    const row = (id, created, updated) => ({
      id,
      server_created_seq: created,
      server_updated_seq: updated,
      title: "Draft copy",
    });

    const hold = (item) =>
      LocalDatabase.putRow(TASK, LocalDatabase.holdNumbers(TASK, item));

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [TASK]: {
            attributes: {
              id: "uuid",
              server_created_seq: "integer",
              server_updated_seq: "integer",
              title: "string",
            },
            relationships: {},
            serverOnly: [],
          },
        },
      };

      Model.reset();
    });

    afterEach(() => {
      delete globalThis.Hologram.sync;
      Model.reset();
    });

    it("is null until the server tells one", () => {
      assert.isNull(LocalDatabase.finalSeq());
    });

    // The point a fill's marker gives its type, which numbers of other types don't reach.
    describe("raiseTypeFinal()", () => {
      const NOTE = "MyApp.Note";

      const created = (type, id) =>
        LocalDatabase.baseRow(type, id).server_created_seq;

      const holdNote = (item) =>
        LocalDatabase.putRow(NOTE, LocalDatabase.holdNumbers(NOTE, item));

      beforeEach(() => {
        Model.reset();

        globalThis.Hologram.sync.model[NOTE] =
          globalThis.Hologram.sync.model[TASK];
      });

      it("files the waiting numbers of the given types, and only those", () => {
        hold(row("t1", 80, 80));
        holdNote(row("n1", 80, 80));

        LocalDatabase.raiseTypeFinal([TASK], 100);

        assert.equal(created(TASK, "t1"), 80);
        assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
        assert.isNull(created(NOTE, "n1"));
        assert.isNull(LocalDatabase.finalSeq());
      });

      it("files a number of the type at or below the point as it comes", () => {
        LocalDatabase.raiseTypeFinal([TASK], 100);

        hold(row("t1", 100, 100));
        hold(row("t2", 101, 101));
        holdNote(row("n1", 90, 90));

        assert.equal(created(TASK, "t1"), 100);
        assert.isNull(created(TASK, "t2"));
        assert.isNull(created(NOTE, "n1"));
      });

      it("keeps the point every type has for the type", () => {
        LocalDatabase.raiseFinal(50);
        LocalDatabase.raiseTypeFinal([TASK], 40);

        hold(row("t1", 45, 45));

        assert.equal(created(TASK, "t1"), 45);
      });

      it("keeps the highest point it was told for the type", () => {
        LocalDatabase.raiseTypeFinal([TASK], 100);
        LocalDatabase.raiseTypeFinal([TASK], 90);
        LocalDatabase.raiseTypeFinal([TASK], null);

        hold(row("t1", 95, 95));

        assert.equal(created(TASK, "t1"), 95);
      });

      it("takes a page's number of the type at or below the point as final", () => {
        LocalDatabase.raiseTypeFinal([TASK], 100);

        const filed = LocalDatabase.carryNumbers(TASK, row("t1", 90, 90));
        const note = LocalDatabase.carryNumbers(NOTE, row("n1", 90, 90));

        assert.equal(filed.server_created_seq, 90);
        assert.isNull(note.server_created_seq);
      });

      for (const [name, end] of [
        ["the marker for everything", () => LocalDatabase.markAllSynced()],
        ["a refill", () => LocalDatabase.beginRefill()],
        ["a lost log", () => LocalDatabase.forgetFinal()],
        [
          "the store's point taken up",
          () => LocalDatabase.takeStoredFinal(null),
        ],
        ["a reset", () => LocalDatabase.reset()],
      ]) {
        it(`drops the type's point on ${name}`, () => {
          LocalDatabase.raiseTypeFinal([TASK], 100);

          end();

          hold(row("t1", 90, 90));

          assert.isNull(created(TASK, "t1"));
        });
      }
    });

    it("files the waiting numbers the point reaches, and only those", () => {
      LocalDatabase.raiseFinal(10);

      hold(row("t1", 12, 12));
      hold(row("t2", 15, 15));

      LocalDatabase.raiseFinal(13);

      assert.equal(LocalDatabase.finalSeq(), 13);
      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_created_seq, 12);
      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_updated_seq, 12);
      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));

      assert.isNull(LocalDatabase.baseRow(TASK, "t2").server_created_seq);
      assert.isNotNull(LocalDatabase.waitingNumbers(TASK, "t2"));
    });

    it("files a waiting number on a copy of the row", () => {
      LocalDatabase.raiseFinal(10);

      hold(row("t1", 12, 12));

      const handed = LocalDatabase.baseRow(TASK, "t1");

      LocalDatabase.raiseFinal(12);

      assert.isNull(handed.server_created_seq);
      assert.notStrictEqual(LocalDatabase.baseRow(TASK, "t1"), handed);
    });

    it("files a big waiting number as a big integer", () => {
      LocalDatabase.raiseFinal(10);

      hold(row("t1", "9007199254740993", "9007199254740993"));

      LocalDatabase.raiseFinal("9007199254740993");

      assert.strictEqual(
        LocalDatabase.baseRow(TASK, "t1").server_created_seq,
        9007199254740993n,
      );
    });

    it("keeps the highest point it was told", () => {
      LocalDatabase.raiseFinal(20);
      LocalDatabase.raiseFinal(15);
      LocalDatabase.raiseFinal(null);

      assert.equal(LocalDatabase.finalSeq(), 20);
    });

    it("files nothing for a point below the one it holds", () => {
      LocalDatabase.raiseFinal(20);

      hold(row("t1", 25, 25));

      LocalDatabase.raiseFinal(15);

      assert.isNull(LocalDatabase.baseRow(TASK, "t1").server_created_seq);
    });

    it("drops the own flag once the created number is filed", () => {
      LocalDatabase.raiseFinal(10);

      hold({...row("t1", 12, 14), $own: true});

      LocalDatabase.raiseFinal(12);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {server_updated_seq: 14},
        own: false,
      });
    });

    it("forgets the point, the waiting numbers and the rows' numbers", () => {
      LocalDatabase.raiseFinal(10);

      hold(row("t1", 5, 5));
      hold(row("t1", 5, 12));

      LocalDatabase.forgetFinal();

      assert.isNull(LocalDatabase.finalSeq());
      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));

      assert.deepStrictEqual(LocalDatabase.baseRow(TASK, "t1"), {
        ...row("t1", 5, 5),
        server_created_seq: null,
        server_updated_seq: null,
      });
    });

    it("forgets a row's numbers on a copy of the row", () => {
      LocalDatabase.raiseFinal(10);

      hold(row("t1", 5, 5));

      const handed = LocalDatabase.baseRow(TASK, "t1");

      LocalDatabase.forgetFinal();

      assert.equal(handed.server_created_seq, 5);
      assert.notStrictEqual(LocalDatabase.baseRow(TASK, "t1"), handed);
    });

    it("leaves a row that holds no numbers as it is", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "Draft copy"});

      const handed = LocalDatabase.baseRow(TASK, "t1");

      LocalDatabase.forgetFinal();

      assert.strictEqual(LocalDatabase.baseRow(TASK, "t1"), handed);
    });

    it("is dropped by a reset, with the waiting numbers", () => {
      LocalDatabase.raiseFinal(10);

      hold(row("t1", 12, 12));

      LocalDatabase.reset();

      assert.isNull(LocalDatabase.finalSeq());
      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });

    it("is kept by a refill, with the waiting numbers", () => {
      LocalDatabase.raiseFinal(10);

      hold(row("t1", 12, 12));

      LocalDatabase.beginRefill({hadPlace: true});

      assert.equal(LocalDatabase.finalSeq(), 10);
      assert.isNotNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });

    it("hands a row's waiting numbers to its record", () => {
      LocalDatabase.raiseFinal(10);

      hold({...row("t1", 12, 12), $own: true});

      const [record] = LocalDatabase.records([`${TASK} t1`]);

      assert.deepStrictEqual(record.waiting, {
        numbers: {server_created_seq: 12, server_updated_seq: 12},
        own: true,
      });

      assert.isNull(record.row.server_created_seq);
    });

    it("hands a record no waiting numbers for a row that waits for none", () => {
      LocalDatabase.raiseFinal(12);

      hold(row("t1", 12, 12));

      assert.notProperty(LocalDatabase.records([`${TASK} t1`])[0], "waiting");
    });

    it("holds a restored row's numbers back again", () => {
      LocalDatabase.restore(
        [
          {
            facts: {},
            id: "t1",
            row: row("t1", 5, 8),
            type: TASK,
            waiting: {numbers: {server_updated_seq: 15}, own: false},
          },
        ],
        10,
      );

      assert.equal(LocalDatabase.finalSeq(), 10);
      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_updated_seq, 8);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {server_updated_seq: 15},
        own: false,
      });
    });

    it("files a restored waiting number the restored point reaches", () => {
      LocalDatabase.restore(
        [
          {
            facts: {},
            id: "t1",
            row: row("t1", 5, 8),
            type: TASK,
            waiting: {numbers: {server_updated_seq: 15}, own: false},
          },
        ],
        15,
      );

      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_updated_seq, 15);
      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });

    // A frame naming no place is stored with its rows filed under the point held then, and the
    // point stored with them is the one written with the last place.
    it("holds a restored row's number above the restored point back", () => {
      LocalDatabase.restore(
        [{facts: {}, id: "t1", row: row("t1", 5, 15), type: TASK}],
        10,
      );

      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_created_seq, 5);
      assert.isNull(LocalDatabase.baseRow(TASK, "t1").server_updated_seq);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {server_updated_seq: 15},
        own: false,
      });
    });

    it("keeps a restored row's newer waiting number over the one it holds above the point", () => {
      LocalDatabase.restore(
        [
          {
            facts: {},
            id: "t1",
            row: row("t1", 12, 15),
            type: TASK,
            waiting: {numbers: {server_updated_seq: 18}, own: false},
          },
        ],
        10,
      );

      assert.isNull(LocalDatabase.baseRow(TASK, "t1").server_created_seq);
      assert.isNull(LocalDatabase.baseRow(TASK, "t1").server_updated_seq);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {server_created_seq: 12, server_updated_seq: 18},
        own: false,
      });
    });

    it("leaves the numbers of a row the page brought above the restored point alone", () => {
      LocalDatabase.putRow(TASK, row("t1", 5, 15));

      LocalDatabase.restore(
        [{facts: {}, id: "t1", row: row("t1", 5, 8), type: TASK}],
        10,
      );

      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_updated_seq, 15);
      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });

    // The page's render hid the numbers, since its pin didn't reach them.
    it("files a stored created number a held row holds none for once the restored point reaches it", () => {
      LocalDatabase.putRow(TASK, row("t1", null, null));

      LocalDatabase.restore(
        [{facts: {}, id: "t1", row: row("t1", 5, 8), type: TASK}],
        10,
      );

      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_created_seq, 5);
      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });

    // A stored updated number can be an older version's than the page brought.
    it("takes no stored updated number a held row holds none for", () => {
      LocalDatabase.putRow(TASK, row("t1", 5, null));

      LocalDatabase.restore(
        [{facts: {}, id: "t1", row: row("t1", 5, 8), type: TASK}],
        10,
      );

      assert.isNull(LocalDatabase.baseRow(TASK, "t1").server_updated_seq);
      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });

    it("holds a stored created number a held row holds none for back above the restored point", () => {
      LocalDatabase.putRow(TASK, row("t1", null, null));

      LocalDatabase.restore(
        [{facts: {}, id: "t1", row: row("t1", 15, 18), type: TASK}],
        10,
      );

      assert.isNull(LocalDatabase.baseRow(TASK, "t1").server_created_seq);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {server_created_seq: 15},
        own: false,
      });
    });

    it("takes no stored created number a held row's shown one is as new as", () => {
      LocalDatabase.raiseFinal(3);
      LocalDatabase.putRow(
        TASK,
        LocalDatabase.carryNumbers(TASK, row("t1", 5, null)),
      );

      LocalDatabase.restore(
        [{facts: {}, id: "t1", row: row("t1", 5, null), type: TASK}],
        4,
      );

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {},
        own: false,
        shown: {server_created_seq: 5},
      });
    });

    // The page showed a newer version's number, so the stored one is an older version's.
    it("takes no stored waiting number a held row's shown one is newer than", () => {
      LocalDatabase.raiseFinal(3);
      LocalDatabase.putRow(
        TASK,
        LocalDatabase.carryNumbers(TASK, row("t1", 2, 20)),
      );

      LocalDatabase.restore(
        [
          {
            facts: {},
            id: "t1",
            row: row("t1", 2, null),
            type: TASK,
            waiting: {numbers: {server_updated_seq: 15}, own: false},
          },
        ],
        10,
      );

      LocalDatabase.raiseFinal(15);

      assert.isNull(LocalDatabase.baseRow(TASK, "t1").server_updated_seq);

      LocalDatabase.raiseFinal(20);

      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_updated_seq, 20);
    });

    it("keeps a newer waiting created number over a stored one a held row holds none for", () => {
      LocalDatabase.raiseFinal(3);
      LocalDatabase.putRow(TASK, row("t1", null, null));
      LocalDatabase.holdNumbers(TASK, {id: "t1", server_created_seq: 15});

      LocalDatabase.restore(
        [{facts: {}, id: "t1", row: row("t1", 5, null), type: TASK}],
        4,
      );

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {server_created_seq: 15},
        own: false,
      });
    });

    it("holds a stored number newer than a carried row's back, own flag and all", () => {
      LocalDatabase.putRow(TASK, row("t1", null, null));

      LocalDatabase.restore(
        [
          {
            facts: {},
            id: "t1",
            row: row("t1", null, null),
            type: TASK,
            waiting: {
              numbers: {server_created_seq: 12, server_updated_seq: 12},
              own: true,
            },
          },
        ],
        10,
      );

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {server_created_seq: 12, server_updated_seq: 12},
        own: true,
      });
    });

    it("takes no stored number a carried row holds a newer one for", () => {
      LocalDatabase.putRow(TASK, row("t1", 12, 20));

      LocalDatabase.restore(
        [
          {
            facts: {},
            id: "t1",
            row: row("t1", null, null),
            type: TASK,
            waiting: {
              numbers: {server_created_seq: 12, server_updated_seq: 14},
              own: true,
            },
          },
        ],
        10,
      );

      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_updated_seq, 20);
    });

    it("takes up a stored row with the numbers the store says it waits for", () => {
      LocalDatabase.raiseFinal(30);

      hold(row("t1", 25, 25));
      hold(row("t1", 25, 40));

      LocalDatabase.takeStoredFinal(10);

      LocalDatabase.putStored(TASK, row("t1", null, null), {
        numbers: {server_created_seq: 12},
        own: true,
      });

      assert.equal(LocalDatabase.finalSeq(), 10);
      assert.isNull(LocalDatabase.baseRow(TASK, "t1").server_created_seq);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {server_created_seq: 12},
        own: true,
      });
    });

    it("holds a stored row's number above the store's point back", () => {
      LocalDatabase.takeStoredFinal(10);
      LocalDatabase.putStored(TASK, row("t1", 5, 15), null);

      assert.isNull(LocalDatabase.baseRow(TASK, "t1").server_updated_seq);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {server_updated_seq: 15},
        own: false,
      });
    });

    // A take-up puts every stored row, so each one settles only itself: settling the whole
    // waiting list per row would read rows times entries.
    it("settles only the stored row it puts", () => {
      LocalDatabase.takeStoredFinal(10);

      const baseRow = sinon.spy(LocalDatabase, "baseRow");

      try {
        for (let i = 0; i < 100; i++) {
          LocalDatabase.putStored(TASK, row(`t${i}`, 15, 15), null);
        }

        assert.isBelow(baseRow.callCount, 1000);
      } finally {
        baseRow.restore();
      }

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t0"), {
        numbers: {server_created_seq: 15, server_updated_seq: 15},
        own: false,
      });
    });

    it("files a number the page showed that the store's point reaches", () => {
      LocalDatabase.carryNumbers(TASK, row("t1", 8, 8));
      LocalDatabase.putRow(TASK, row("t1", null, null));

      LocalDatabase.takeStoredFinal(10);

      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_created_seq, 8);
    });

    it("files a stored row's waiting number the store's point reaches", () => {
      LocalDatabase.takeStoredFinal(12);

      LocalDatabase.putStored(TASK, row("t1", null, null), {
        numbers: {server_created_seq: 12},
        own: true,
      });

      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_created_seq, 12);
      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });

    it("keeps a carried row's numbers above the point beside it as shown", () => {
      LocalDatabase.raiseFinal(10);

      const filed = LocalDatabase.carryNumbers(TASK, row("t1", 12, 14));

      assert.isNull(filed.server_created_seq);
      assert.isNull(filed.server_updated_seq);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {},
        own: false,
        shown: {server_created_seq: 12, server_updated_seq: 14},
      });
    });

    it("carries a row's numbers the point reaches as they came", () => {
      LocalDatabase.raiseFinal(12);

      const filed = LocalDatabase.carryNumbers(TASK, row("t1", 11, 12));

      assert.equal(filed.server_created_seq, 11);
      assert.equal(filed.server_updated_seq, 12);
      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });

    it("carries the number a held row has in place of one above the point", () => {
      LocalDatabase.raiseFinal(10);

      hold(row("t1", 5, 8));

      const filed = LocalDatabase.carryNumbers(TASK, row("t1", 5, 14));

      assert.equal(filed.server_updated_seq, 8);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {},
        own: false,
        shown: {server_updated_seq: 14},
      });
    });

    it("keeps the newest number a page showed", () => {
      LocalDatabase.raiseFinal(10);

      LocalDatabase.carryNumbers(TASK, row("t1", 12, 14));
      LocalDatabase.carryNumbers(TASK, row("t1", 12, 13));

      assert.equal(
        LocalDatabase.waitingNumbers(TASK, "t1").shown.server_updated_seq,
        14,
      );
    });

    it("files a shown number the point reaches while a newer one waits", () => {
      LocalDatabase.raiseFinal(10);

      hold(row("t1", 5, 8));
      LocalDatabase.carryNumbers(TASK, row("t1", 5, 14));
      hold(row("t1", 5, 16));

      LocalDatabase.raiseFinal(14);

      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_updated_seq, 14);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {server_updated_seq: 16},
        own: false,
      });
    });

    it("files the higher of a shown and a waiting number the point reaches", () => {
      LocalDatabase.raiseFinal(10);

      hold(row("t1", 12, 18));
      LocalDatabase.carryNumbers(TASK, row("t1", 12, 15));

      LocalDatabase.raiseFinal(20);

      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_created_seq, 12);
      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_updated_seq, 18);
      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });

    it("files the shown number when it is the higher one the point reaches", () => {
      LocalDatabase.raiseFinal(10);

      hold(row("t1", 12, 15));
      LocalDatabase.carryNumbers(TASK, row("t1", 12, 18));

      LocalDatabase.raiseFinal(20);

      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_updated_seq, 18);
      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });

    it("hands a row's shown numbers to its record and takes them back", () => {
      LocalDatabase.raiseFinal(10);

      hold(row("t1", 5, 8));
      LocalDatabase.carryNumbers(TASK, row("t1", 5, 14));

      const [record] = LocalDatabase.records([`${TASK} t1`]);

      assert.deepStrictEqual(record.waiting, {
        numbers: {},
        own: false,
        shown: {server_updated_seq: 14},
      });

      LocalDatabase.reset();
      LocalDatabase.restore([record], 10);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {},
        own: false,
        shown: {server_updated_seq: 14},
      });
    });

    it("keeps a row's shown numbers when the store's copy is taken up", () => {
      LocalDatabase.raiseFinal(10);

      hold(row("t1", 5, 8));
      LocalDatabase.carryNumbers(TASK, row("t1", 5, 14));

      LocalDatabase.takeStoredFinal(10);
      LocalDatabase.putStored(TASK, row("t1", 5, 8), null);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {},
        own: false,
        shown: {server_updated_seq: 14},
      });
    });

    it("moves a carried row's numbers above a lower stored point beside it", () => {
      LocalDatabase.raiseFinal(20);

      LocalDatabase.putRow(
        TASK,
        LocalDatabase.carryNumbers(TASK, row("t1", 12, 15)),
      );

      LocalDatabase.markCarried(TASK, "t1");

      LocalDatabase.takeStoredFinal(12);

      const held = LocalDatabase.baseRow(TASK, "t1");

      assert.equal(held.server_created_seq, 12);
      assert.isNull(held.server_updated_seq);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {},
        own: false,
        shown: {server_updated_seq: 15},
      });
    });

    it("leaves the numbers of a row a page didn't carry to the store", () => {
      LocalDatabase.raiseFinal(20);

      hold(row("t1", 12, 15));

      LocalDatabase.takeStoredFinal(12);

      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_updated_seq, 15);
      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });

    // The numbers a page's render hid because they weren't final under its limit, which its row
    // carries beside its data.
    describe("a page row's hidden numbers", () => {
      const hidden = (id, waiting) =>
        Object.assign(row(id, null, null), {$waiting: waiting});

      const carry = (item) =>
        Deltas.apply({put_entity: {[TASK]: [item]}}, {insertOnly: true});

      // A reload's page is applied before the store is restored, so no point is held yet, and the
      // stored place can be past the hidden numbers, so catch-up never sends the row again.
      it("files them once a reload restores a point that reaches them", () => {
        carry(hidden("t1", {server_created_seq: 5, server_updated_seq: 8}));

        LocalDatabase.restore(
          [{facts: {}, id: "t1", row: row("t1", 5, 8), type: TASK}],
          10,
        );

        const held = LocalDatabase.baseRow(TASK, "t1");

        assert.equal(held.server_created_seq, 5);
        assert.equal(held.server_updated_seq, 8);
        assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
      });

      it("files one the point reaches straight into the row", () => {
        LocalDatabase.raiseFinal(10);

        carry(hidden("t1", {server_updated_seq: 8}));

        assert.equal(LocalDatabase.baseRow(TASK, "t1").server_updated_seq, 8);
        assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
      });

      it("holds one above the point back until the point reaches it", () => {
        LocalDatabase.raiseFinal(10);

        carry(hidden("t1", {server_updated_seq: 12}));

        assert.isNull(LocalDatabase.baseRow(TASK, "t1").server_updated_seq);

        assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
          numbers: {server_updated_seq: 12},
          own: false,
        });

        LocalDatabase.raiseFinal(12);

        assert.equal(LocalDatabase.baseRow(TASK, "t1").server_updated_seq, 12);
        assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
      });

      it("keeps a newer number already waiting for the field", () => {
        LocalDatabase.raiseFinal(10);

        LocalDatabase.holdNumbers(TASK, row("t1", 5, 15));

        LocalDatabase.carryNumbers(
          TASK,
          hidden("t1", {server_updated_seq: 12}),
        );

        assert.equal(
          LocalDatabase.waitingNumbers(TASK, "t1").numbers.server_updated_seq,
          15,
        );
      });

      it("holds back a number past 2^53 the wire spells as text", () => {
        LocalDatabase.raiseFinal(10);

        carry(hidden("t1", {server_updated_seq: "9007199254740993"}));

        assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
          numbers: {server_updated_seq: "9007199254740993"},
          own: false,
        });

        LocalDatabase.raiseFinal("9007199254740993");

        assert.strictEqual(
          LocalDatabase.baseRow(TASK, "t1").server_updated_seq,
          9007199254740993n,
        );
      });

      it("leaves them off the row it files", () => {
        LocalDatabase.raiseFinal(10);

        carry(hidden("t1", {server_updated_seq: 8}));

        assert.notProperty(LocalDatabase.baseRow(TASK, "t1"), "$waiting");
      });

      // The held row's values aren't the page's version, so the page's numbers aren't its own.
      it("ignores them for a row held already", () => {
        LocalDatabase.raiseFinal(10);

        hold(row("t1", 5, null));

        carry(hidden("t1", {server_updated_seq: 8}));
        carry(hidden("t1", {server_updated_seq: 12}));

        assert.isNull(LocalDatabase.baseRow(TASK, "t1").server_updated_seq);
        assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
      });
    });
  });

  describe("orderingKey()", () => {
    const TASK = "MyApp.Task";
    const SAVED_AT = "2026-11-24T10:00:00.000000Z";

    const row = (id, created, updated, extra = {}) =>
      Object.assign(
        {
          id,
          server_created_at: SAVED_AT,
          server_created_seq: created,
          server_updated_seq: updated,
          title: "Draft copy",
        },
        extra,
      );

    const hold = (item) =>
      LocalDatabase.putRow(TASK, LocalDatabase.holdNumbers(TASK, item));

    const key = (id, field = "server_updated_seq") =>
      LocalDatabase.orderingKey(TASK, LocalDatabase.baseRow(TASK, id), field);

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [TASK]: {
            attributes: {
              id: "uuid",
              server_created_at: "utc_datetime_usec",
              server_created_seq: "integer",
              server_updated_seq: "integer",
              title: "string",
            },
            relationships: {},
            serverOnly: [],
          },
        },
      };

      Model.reset();
      LocalDatabase.raiseFinal(10);
    });

    afterEach(() => {
      delete globalThis.Hologram.sync;
      Model.reset();
    });

    it("places a row by its number final here", () => {
      hold(row("t1", 5, 8));

      assert.deepStrictEqual(key("t1"), [0, 8]);
    });

    it("places a row by the number a page showed above its own", () => {
      hold(row("t1", 5, 8));
      LocalDatabase.carryNumbers(TASK, row("t1", 5, 14));

      assert.deepStrictEqual(key("t1"), [0, 14]);
    });

    it("places a row by a big number a page showed as a big integer", () => {
      hold(row("t1", 5, 8));
      LocalDatabase.carryNumbers(TASK, row("t1", 5, "9007199254740995"));

      assert.deepStrictEqual(key("t1"), [0, 9007199254740995n]);
    });

    it("places a stranger's row whose number waits after the numbered ones", () => {
      hold(row("t1", 12, 12));

      assert.deepStrictEqual(key("t1"), [1, null]);
    });

    it("places this client's own row by the number it waits for", () => {
      hold(row("t1", 12, 14, {$own: true}));

      assert.deepStrictEqual(key("t1"), [2, 14]);
      assert.deepStrictEqual(key("t1", "server_created_seq"), [2, 12]);
    });

    it("places an own row waiting for no updated number by its created one", () => {
      hold(row("t1", 12, null, {$own: true}));

      assert.deepStrictEqual(key("t1"), [2, 12]);
    });

    it("places a big waiting number as a big integer", () => {
      hold(row("t1", "9007199254740993", "9007199254740995", {$own: true}));

      assert.deepStrictEqual(key("t1"), [2, 9007199254740995n]);
    });

    it("places a row the server hasn't saved last", () => {
      LocalDatabase.putRow(
        TASK,
        row("t1", null, null, {server_created_at: null}),
      );

      assert.deepStrictEqual(key("t1"), [3, null]);
    });
  });

  describe("reset()", () => {
    it("drops the rows, the facts, the completeness marks and what a page carried", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");
      LocalDatabase.markCarried("MyApp.Task", "t1");
      LocalDatabase.markTypesSynced(["MyApp.Project"]);
      LocalDatabase.markAllSynced();

      LocalDatabase.reset();

      assert.deepEqual(LocalDatabase.carriedEntries(), []);

      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t1"));

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(),
      );

      assert.isFalse(LocalDatabase.isAllSynced());
      assert.isFalse(LocalDatabase.isTypeSynced("MyApp.Project"));
    });
  });
});
