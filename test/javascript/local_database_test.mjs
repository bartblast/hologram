"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

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

  describe("isSynced()", () => {
    it("answers false before the scope's marker arrived", () => {
      assert.isFalse(LocalDatabase.isSynced("page"));
    });

    it("answers true once the scope is marked", () => {
      LocalDatabase.markSynced("page");

      assert.isTrue(LocalDatabase.isSynced("page"));
    });

    it("marks each scope on its own", () => {
      LocalDatabase.markSynced("page");

      assert.isFalse(LocalDatabase.isSynced("all"));
    });
  });

  describe("markSynced()", () => {
    // What a page still carries when the whole pot declares itself complete was never this
    // client's to hold - a grant revoked between the render and the connect leaves exactly that.
    it("drops a carried row the fill never delivered", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});
      LocalDatabase.markCarried("MyApp.Task", "t1");

      LocalDatabase.markSynced("all");

      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t1"));
      assert.deepEqual(LocalDatabase.carriedEntries(), []);
    });

    it("keeps a carried row the fill delivered", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});
      LocalDatabase.markCarried("MyApp.Task", "t1");
      LocalDatabase.unmarkCarried("MyApp.Task", "t1");

      LocalDatabase.markSynced("all");

      assert.deepEqual(LocalDatabase.getRow("MyApp.Task", "t1"), {
        id: "t1",
        title: "Draft copy",
      });
    });

    it("keeps a row no page carried", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});

      LocalDatabase.markSynced("all");

      assert.deepEqual(LocalDatabase.getRow("MyApp.Task", "t1"), {
        id: "t1",
        title: "Draft copy",
      });
    });

    // The page scope says one page's rows are complete, which says nothing about a row another
    // page carried - only the whole pot's marker can call one an orphan.
    it("sweeps nothing at the page scope", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});
      LocalDatabase.markCarried("MyApp.Task", "t1");

      LocalDatabase.markSynced("page");

      assert.deepEqual(LocalDatabase.carriedEntries(), [["MyApp.Task", "t1"]]);
      assert.isNotNull(LocalDatabase.getRow("MyApp.Task", "t1"));
    });

    // A swept row takes its relationship facts with it, the way any row leaving the pot does.
    it("takes the swept row's relationship facts with it", () => {
      LocalDatabase.putRow("MyApp.Project", {id: "p1", name: "Board"});
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");
      LocalDatabase.markCarried("MyApp.Project", "p1");

      LocalDatabase.markSynced("all");

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(),
      );
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

    // The model is read for one thing only - which of a type's relationships are to-many - so what
    // is baked here is that and the little Model.entry insists on.
    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [TAG]: {
            attributes: {id: "uuid", name: "string"},
            enumValues: {},
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

  describe("reset()", () => {
    it("drops the rows, the facts, the scope marks and what a page carried", () => {
      LocalDatabase.putRow("MyApp.Task", {id: "t1", title: "Draft copy"});
      LocalDatabase.addFact("MyApp.Project", "tasks", "p1", "t1");
      LocalDatabase.markCarried("MyApp.Task", "t1");
      LocalDatabase.markSynced("page");

      LocalDatabase.reset();

      assert.deepEqual(LocalDatabase.carriedEntries(), []);

      assert.isNull(LocalDatabase.getRow("MyApp.Task", "t1"));

      assert.deepEqual(
        LocalDatabase.getTargetIds("MyApp.Project", "tasks", "p1"),
        new Set(),
      );

      assert.isFalse(LocalDatabase.isSynced("page"));
    });
  });
});
