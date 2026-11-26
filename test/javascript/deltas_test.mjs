"use strict";

import {assert, defineRuntimeGlobals, sinon} from "./support/helpers.mjs";

import Batch from "../../assets/js/batch.mjs";
import Clock from "../../assets/js/clock.mjs";
import Deltas from "../../assets/js/deltas.mjs";
import DropHash from "../../assets/js/drop_hash.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Model from "../../assets/js/model.mjs";
import Overlay from "../../assets/js/overlay.mjs";

defineRuntimeGlobals();

describe("Deltas", () => {
  const PROJECT = "MyApp.Project";
  const TASK = "MyApp.Task";

  beforeEach(() => {
    globalThis.Hologram.sync = {
      model: {
        [PROJECT]: {
          attributes: {id: "id", name: "string"},
          relationships: {
            owner: {toMany: false, type: "MyApp.User"},
            tasks: {toMany: true, type: TASK},
          },
          serverOnly: [],
        },
        [TASK]: {
          attributes: {
            done: "boolean",
            id: "id",
            note: "string",
            position: "integer",
            title: "string",
          },
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

    Clock.reset();
    Deltas.reset();
    LocalDatabase.reset();
    Model.reset();
    Overlay.reset();
  });

  afterEach(() => {
    Overlay.reset();
  });

  describe("apply() - put_entity", () => {
    it("files the row under its type and id", () => {
      Deltas.apply({
        put_entity: {[TASK]: [{done: false, id: "t1", title: "Draft copy"}]},
      });

      const row = LocalDatabase.getRow(TASK, "t1");

      assert.equal(row.id, "t1");
      assert.equal(row.title, "Draft copy");
      assert.isFalse(row.done);
    });

    it("files the row's revisions beside its attributes", () => {
      Deltas.apply({
        put_entity: {
          [TASK]: [
            {
              done: false,
              id: "t1",
              title: "Draft copy",
              $revisions: {title: 3},
            },
          ],
        },
      });

      assert.deepEqual(LocalDatabase.getRow(TASK, "t1").$revisions, {title: 3});
    });

    it("records the target ids a to-many relationship names as facts", () => {
      Deltas.apply({
        put_entity: {
          [PROJECT]: [{id: "p1", name: "Website", tasks: ["t1", "t2"]}],
        },
      });

      assert.deepEqual(
        LocalDatabase.getTargetIds(PROJECT, "tasks", "p1"),
        new Set(["t1", "t2"]),
      );
    });

    // An inverse of a to-many is held as the ids the server read for the row, kept current by the
    // edges it reports for them - so it is filed the way a to-many's ids are.
    it("records the ids an inverse of a to-many names as facts", () => {
      Deltas.apply({
        put_entity: {
          [TASK]: [{id: "t1", owners: ["p1", "p2"], title: "Draft"}],
        },
      });

      assert.deepEqual(
        LocalDatabase.getTargetIds(TASK, "owners", "t1"),
        new Set(["p1", "p2"]),
      );

      assert.notProperty(LocalDatabase.baseRow(TASK, "t1"), "owners");
    });

    // The pot is flat: what a row states about a relationship lives in the facts, so a row left
    // holding its own target ids would be answered from two places that can disagree.
    it("keeps the relationship out of the filed row", () => {
      Deltas.apply({
        put_entity: {[PROJECT]: [{id: "p1", name: "Website", tasks: ["t1"]}]},
      });

      assert.deepEqual(LocalDatabase.getRow(PROJECT, "p1"), {
        id: "p1",
        name: "Website",
        name$sort: "website",
      });
    });

    it("replaces the target set a repeated row states", () => {
      Deltas.apply({
        put_entity: {
          [PROJECT]: [{id: "p1", name: "Website", tasks: ["t1", "t2"]}],
        },
      });

      Deltas.apply({
        put_entity: {[PROJECT]: [{id: "p1", name: "Website", tasks: ["t2"]}]},
      });

      assert.deepEqual(
        LocalDatabase.getTargetIds(PROJECT, "tasks", "p1"),
        new Set(["t2"]),
      );
    });

    // What the keys themselves are is Model.computeSortKeys's, and its own tests say so - what a
    // filed row proves is that filing asks for them at all.
    it("files a sort key beside the string attribute it derives from", () => {
      Deltas.apply({
        put_entity: {[TASK]: [{done: false, id: "t1", title: "Łódź"}]},
      });

      assert.equal(LocalDatabase.getRow(TASK, "t1").title$sort, "lodz");
    });

    it("files every row of every type a frame carries", () => {
      Deltas.apply({
        put_entity: {
          [PROJECT]: [{id: "p1", name: "Website"}],
          [TASK]: [
            {done: false, id: "t1", title: "Draft copy"},
            {done: false, id: "t2", title: "Ship it"},
          ],
        },
      });

      assert.equal(LocalDatabase.getRow(PROJECT, "p1").name, "Website");
      assert.equal(LocalDatabase.getRow(TASK, "t1").title, "Draft copy");
      assert.equal(LocalDatabase.getRow(TASK, "t2").title, "Ship it");
    });
  });

  describe("apply() - rows a page carried", () => {
    const carry = (rows) =>
      Deltas.apply({put_entity: {[TASK]: rows}}, {insertOnly: true});

    it("files a row the client does not hold", () => {
      carry([{done: false, id: "t1", title: "Draft copy"}]);

      assert.equal(LocalDatabase.getRow(TASK, "t1").title, "Draft copy");
    });

    // What a page carries can be OLDER than what the client holds: a page rendered at one moment
    // lands after the stream delivered a later change to the same row, and overwriting would put
    // back a value nothing will correct.
    it("leaves a row the client already holds alone", () => {
      Deltas.apply({
        put_entity: {
          [TASK]: [{done: false, id: "t1", title: "from the stream"}],
        },
      });

      carry([{done: false, id: "t1", title: "from the page"}]);

      assert.equal(LocalDatabase.getRow(TASK, "t1").title, "from the stream");
    });

    it("files the rows the client lacks and no others", () => {
      Deltas.apply({
        put_entity: {
          [TASK]: [{done: false, id: "t1", title: "from the stream"}],
        },
      });

      carry([
        {done: false, id: "t1", title: "from the page"},
        {done: false, id: "t2", title: "new to the client"},
      ]);

      assert.equal(LocalDatabase.getRow(TASK, "t1").title, "from the stream");
      assert.equal(LocalDatabase.getRow(TASK, "t2").title, "new to the client");
    });

    it("remembers what it filed as unconfirmed by the stream", () => {
      carry([{done: false, id: "t1", title: "Draft copy"}]);

      assert.deepEqual(LocalDatabase.carriedEntries(), [[TASK, "t1"]]);
    });

    it("remembers nothing for a row it left alone", () => {
      Deltas.apply({
        put_entity: {
          [TASK]: [{done: false, id: "t1", title: "from the stream"}],
        },
      });

      carry([{done: false, id: "t1", title: "from the page"}]);

      assert.deepEqual(LocalDatabase.carriedEntries(), []);
    });

    // Once the stream delivers it, it is no longer a row the client has only because a page said
    // so - and no longer one the completeness marker should take away.
    it("forgets a carried row the stream then delivers", () => {
      carry([{done: false, id: "t1", title: "from the page"}]);

      Deltas.apply({
        put_entity: {
          [TASK]: [{done: false, id: "t1", title: "from the stream"}],
        },
      });

      assert.deepEqual(LocalDatabase.carriedEntries(), []);
      assert.equal(LocalDatabase.getRow(TASK, "t1").title, "from the stream");
    });

    it("files the relationship facts of a row it files", () => {
      Deltas.apply(
        {put_entity: {[PROJECT]: [{id: "p1", name: "Website", tasks: ["t1"]}]}},
        {insertOnly: true},
      );

      assert.deepEqual(
        LocalDatabase.getTargetIds(PROJECT, "tasks", "p1"),
        new Set(["t1"]),
      );
    });

    it("derives sort keys the way the stream's rows get them", () => {
      carry([{done: false, id: "t1", title: "Łódź"}]);

      assert.equal(LocalDatabase.getRow(TASK, "t1").title$sort, "lodz");
    });
  });

  describe("apply() - big integers", () => {
    it("holds an integer that arrives as text as a BigInt", () => {
      Deltas.apply({
        put_entity: {[TASK]: [{id: "t1", position: "9007199254740993"}]},
      });

      assert.strictEqual(
        LocalDatabase.getRow(TASK, "t1").position,
        9007199254740993n,
      );
    });

    it("leaves an integer that arrives as a number a Number", () => {
      Deltas.apply({put_entity: {[TASK]: [{id: "t1", position: 42}]}});

      assert.strictEqual(LocalDatabase.getRow(TASK, "t1").position, 42);
    });

    it("leaves text in a string attribute as it is", () => {
      Deltas.apply({
        put_entity: {[TASK]: [{id: "t1", title: "9007199254740993"}]},
      });

      assert.strictEqual(
        LocalDatabase.getRow(TASK, "t1").title,
        "9007199254740993",
      );
    });

    it("holds a patched integer that arrives as text as a BigInt", () => {
      Deltas.apply({put_entity: {[TASK]: [{id: "t1", position: 1}]}});

      Deltas.apply({
        patch_entity: {[TASK]: [{id: "t1", position: "-9007199254740993"}]},
      });

      assert.strictEqual(
        LocalDatabase.getRow(TASK, "t1").position,
        -9007199254740993n,
      );
    });

    it("keeps a held BigInt a patch doesn't name", () => {
      Deltas.apply({
        put_entity: {[TASK]: [{id: "t1", position: "9007199254740993"}]},
      });

      Deltas.apply({patch_entity: {[TASK]: [{id: "t1", title: "Ship it"}]}});

      assert.strictEqual(
        LocalDatabase.getRow(TASK, "t1").position,
        9007199254740993n,
      );
    });
  });

  describe("apply() - patch_entity", () => {
    beforeEach(() => {
      Deltas.apply({
        put_entity: {[TASK]: [{done: false, id: "t1", title: "Draft copy"}]},
      });
    });

    it("writes the attributes the patch names", () => {
      Deltas.apply({patch_entity: {[TASK]: [{id: "t1", title: "Ship it"}]}});

      assert.equal(LocalDatabase.getRow(TASK, "t1").title, "Ship it");
    });

    it("leaves the attributes the patch does not name", () => {
      Deltas.apply({patch_entity: {[TASK]: [{id: "t1", title: "Ship it"}]}});

      assert.isFalse(LocalDatabase.getRow(TASK, "t1").done);
    });

    it("computes the sort key again from the value that moved", () => {
      Deltas.apply({patch_entity: {[TASK]: [{id: "t1", title: "Zürich"}]}});

      assert.equal(LocalDatabase.getRow(TASK, "t1").title$sort, "zurich");
    });

    // A patch is a bag of attributes, and the row it merges into is the FILED one, whose
    // relationships were split out into the facts when it was filed - so a patch carries nothing
    // that could restate a target set, however many edges ride in the same frame.
    it("leaves the row's relationship facts alone", () => {
      Deltas.apply({
        put_entity: {[PROJECT]: [{id: "p1", name: "Website", tasks: ["t1"]}]},
      });

      Deltas.apply({patch_entity: {[PROJECT]: [{id: "p1", name: "Intranet"}]}});

      assert.deepEqual(
        LocalDatabase.getTargetIds(PROJECT, "tasks", "p1"),
        new Set(["t1"]),
      );
    });

    it("writes the patch's revisions over the row's and leaves the rest", () => {
      Deltas.apply({
        put_entity: {
          [TASK]: [
            {
              done: false,
              id: "t1",
              title: "Draft copy",
              $revisions: {done: 1, title: 1},
            },
          ],
        },
      });

      Deltas.apply({
        patch_entity: {
          [TASK]: [{id: "t1", title: "Ship it", $revisions: {title: 2}}],
        },
      });

      assert.deepEqual(LocalDatabase.getRow(TASK, "t1").$revisions, {
        done: 1,
        title: 2,
      });
    });

    it("replaces the row's verdicts with a patch's and keeps its revisions", () => {
      Deltas.apply({
        put_entity: {
          [TASK]: [
            {
              done: false,
              id: "t1",
              title: "Draft copy",
              $revisions: {done: 1, title: 1},
              $verdicts: {"delete:aa": true, "update:bb": true},
            },
          ],
        },
      });

      Deltas.apply({
        patch_entity: {
          [TASK]: [{id: "t1", $revisions: {}, $verdicts: {"delete:aa": false}}],
        },
      });

      const row = LocalDatabase.getRow(TASK, "t1");

      assert.deepEqual(row.$verdicts, {"delete:aa": false});
      assert.deepEqual(row.$revisions, {done: 1, title: 1});
    });

    it("leaves the map alone for a patch carrying no revisions", () => {
      Deltas.apply({
        put_entity: {
          [TASK]: [
            {
              done: false,
              id: "t1",
              title: "Draft copy",
              $revisions: {done: 1, title: 1},
            },
          ],
        },
      });

      Deltas.apply({patch_entity: {[TASK]: [{id: "t1", title: "Ship it"}]}});

      assert.deepEqual(LocalDatabase.getRow(TASK, "t1").$revisions, {
        done: 1,
        title: 1,
      });
    });

    // A patch names a row the client was told about, so one it does not hold is one it has been
    // told to let go of - filing the changes alone would leave a row with holes.
    it("passes over a row the client does not hold", () => {
      Deltas.apply({patch_entity: {[TASK]: [{id: "t9", title: "Ship it"}]}});

      assert.isNull(LocalDatabase.getRow(TASK, "t9"));
    });
  });

  describe("apply() - the clock's receive rule", () => {
    // Frozen, so every expectation below is this millisecond's stamp rather than whatever the
    // machine's clock reads between the revision being written and the stamp being taken.
    const nowMs = 1_756_100_000_123;

    let timers;

    beforeEach(() => {
      timers = sinon.useFakeTimers(nowMs);
    });

    afterEach(() => {
      timers.restore();
    });

    it("advances past every revision a put carries", () => {
      Deltas.apply({
        put_entity: {
          [TASK]: [
            {
              done: false,
              id: "t1",
              title: "Draft copy",
              $revisions: {
                done: nowMs * 1024 + 5000,
                title: nowMs * 1024 + 9000,
              },
            },
          ],
        },
      });

      assert.equal(Clock.stamp(), nowMs * 1024 + 9001);
    });

    it("advances past every revision a patch carries", () => {
      Deltas.apply({
        put_entity: {[TASK]: [{done: false, id: "t1", title: "Draft copy"}]},
      });

      Deltas.apply({
        patch_entity: {
          [TASK]: [
            {
              id: "t1",
              title: "Ship it",
              $revisions: {title: nowMs * 1024 + 7000},
            },
          ],
        },
      });

      assert.equal(Clock.stamp(), nowMs * 1024 + 7001);
    });

    // The rule is about what arrived, not about what was kept. Neither this case nor the carried
    // one below can reach a based_on today - the client either lacks the row or holds a filed copy
    // whose own revisions it observed - so what these two pin is the placement, not a bug they
    // would otherwise let through.
    it("advances past the revisions of a patch for a row it does not hold", () => {
      Deltas.apply({
        patch_entity: {
          [TASK]: [
            {
              id: "t9",
              title: "Ship it",
              $revisions: {title: nowMs * 1024 + 3000},
            },
          ],
        },
      });

      assert.equal(Clock.stamp(), nowMs * 1024 + 3001);
    });

    it("advances past the revisions of a carried row it leaves alone", () => {
      Deltas.apply({
        put_entity: {[TASK]: [{done: false, id: "t1", title: "Draft copy"}]},
      });

      Deltas.apply(
        {
          put_entity: {
            [TASK]: [
              {
                done: false,
                id: "t1",
                title: "Carried copy",
                $revisions: {title: nowMs * 1024 + 4000},
              },
            ],
          },
        },
        {insertOnly: true},
      );

      assert.equal(LocalDatabase.getRow(TASK, "t1").title, "Draft copy");
      assert.equal(Clock.stamp(), nowMs * 1024 + 4001);
    });

    it("leaves the clock alone for a row carrying no revisions", () => {
      Deltas.apply({
        put_entity: {[TASK]: [{done: false, id: "t1", title: "Draft copy"}]},
      });

      assert.equal(Clock.stamp(), nowMs * 1024);
    });
  });

  // A frame is a statement about the SERVER's row, so what ingest asks is what the server last
  // said - never what this client has written and not yet sent. Reading the folded row instead
  // would let a frame file a row into the base on the strength of a create the server has never
  // seen.
  describe("apply() - against a row that is only a pending write", () => {
    beforeEach(() => {
      const batch = new Batch("cid");

      batch.append({
        data: {done: false, title: "Mine, unsent"},
        id: "t9",
        op: "create",
        stamp: 1024,
        type: TASK,
      });

      Overlay.push(batch);
    });

    it("passes a patch over, as it does for any row the server has not sent", () => {
      Deltas.apply({patch_entity: {[TASK]: [{id: "t9", title: "Ship it"}]}});

      assert.isNull(LocalDatabase.baseRow(TASK, "t9"));
      assert.equal(LocalDatabase.getRow(TASK, "t9").title, "Mine, unsent");
    });

    it("files a carried row, which the client does not yet hold from the server", () => {
      Deltas.apply(
        {
          put_entity: {
            [TASK]: [{done: true, id: "t9", title: "From the page"}],
          },
        },
        {insertOnly: true},
      );

      assert.equal(LocalDatabase.baseRow(TASK, "t9").title, "From the page");
    });
  });

  describe("apply() - unsync_entity", () => {
    it("drops the row", () => {
      Deltas.apply({
        put_entity: {[TASK]: [{done: false, id: "t1", title: "Draft copy"}]},
      });

      Deltas.apply({unsync_entity: {[TASK]: ["t1"]}});

      assert.isNull(LocalDatabase.getRow(TASK, "t1"));
    });

    it("drops the row's relationship facts with it", () => {
      Deltas.apply({
        put_entity: {[PROJECT]: [{id: "p1", name: "Website", tasks: ["t1"]}]},
      });

      Deltas.apply({unsync_entity: {[PROJECT]: ["p1"]}});

      assert.deepEqual(
        LocalDatabase.getTargetIds(PROJECT, "tasks", "p1"),
        new Set(),
      );
    });

    // The answer to a batch of this client's can file a pair after the server read the pairs it
    // tells with this drop, so the frame says nothing of it.
    describe("a pair naming the row, filed under a row still held", () => {
      beforeEach(() => {
        Deltas.apply({
          put_entity: {
            [PROJECT]: [{id: "p1", name: "Website", tasks: ["t1", "t2"]}],
            [TASK]: [
              {done: false, id: "t1", owners: ["p1"], title: "One"},
              {done: false, id: "t2", owners: ["p1"], title: "Two"},
            ],
          },
        });
      });

      it("takes the pair and leaves one naming another row", () => {
        Deltas.apply({unsync_entity: {[TASK]: ["t1"]}});

        assert.deepEqual(
          LocalDatabase.baseTargetIds(PROJECT, "tasks", "p1"),
          new Set(["t2"]),
        );
      });

      it("takes the inverse pair when the source leaves", () => {
        Deltas.apply({unsync_entity: {[PROJECT]: ["p1"]}});

        assert.deepEqual(
          LocalDatabase.baseTargetIds(TASK, "owners", "t1"),
          new Set(),
        );
      });

      it("takes the pairs of rows a frame both deleted and unsynced", () => {
        Deltas.apply({
          del_entity: {[TASK]: ["t1"]},
          unsync_entity: {[TASK]: ["t2"]},
        });

        assert.deepEqual(
          LocalDatabase.baseTargetIds(PROJECT, "tasks", "p1"),
          new Set(),
        );
      });

      // Naming the holder as written would have the frame's number land its pending writes.
      it("queues the pair for the stored set without writing the holder", () => {
        const written = Deltas.apply({unsync_entity: {[TASK]: ["t1"]}});

        assert.deepEqual(LocalDatabase.takeStoredFactRemovals(), [
          {id: "p1", relationship: "tasks", targetIds: ["t1"], type: PROJECT},
        ]);

        assert.deepEqual(written, new Set([`${TASK} t1`]));
      });
    });
  });

  describe("apply() - unsync_hashed", () => {
    const SALT = "q3Vx";

    const hashedDrop = (type, ids, salt = SALT) => ({
      unsync_hashed: {
        [type]: [{hashes: ids.map((id) => DropHash.hash(salt, id)), salt}],
      },
    });

    beforeEach(() => {
      Deltas.apply({
        put_entity: {
          [PROJECT]: [{id: "p1", name: "Website", tasks: ["t1", "t2"]}],
          [TASK]: [
            {done: false, id: "t1", owners: ["p1"], title: "Draft copy"},
            {done: false, id: "t2", owners: ["p1"], title: "Review copy"},
          ],
        },
      });
    });

    it("drops a held row whose id hashes to one it was sent", () => {
      Deltas.apply(hashedDrop(TASK, ["t1"]));

      assert.isNull(LocalDatabase.getRow(TASK, "t1"));
      assert.isNotNull(LocalDatabase.getRow(TASK, "t2"));
    });

    it("drops nothing for a hash no held row has", () => {
      Deltas.apply(hashedDrop(TASK, ["t9"]));

      assert.isNotNull(LocalDatabase.getRow(TASK, "t1"));
      assert.isNotNull(LocalDatabase.getRow(TASK, "t2"));
    });

    it("drops nothing for a hash under another salt", () => {
      const deltas = hashedDrop(TASK, ["t1"], "other");
      deltas.unsync_hashed[TASK][0].salt = SALT;

      Deltas.apply(deltas);

      assert.isNotNull(LocalDatabase.getRow(TASK, "t1"));
    });

    it("drops nothing for a type it holds no row of", () => {
      Deltas.apply(hashedDrop("MyApp.User", ["t1"]));

      assert.isNotNull(LocalDatabase.getRow(TASK, "t1"));
    });

    it("takes the row out of the sets of the rows it still holds", () => {
      Deltas.apply(hashedDrop(TASK, ["t1"]));

      assert.deepEqual(
        LocalDatabase.getTargetIds(PROJECT, "tasks", "p1"),
        new Set(["t2"]),
      );
    });

    it("takes the row out of the inverse sets of the rows it still holds", () => {
      Deltas.apply(hashedDrop(PROJECT, ["p1"]));

      assert.deepEqual(
        LocalDatabase.getTargetIds(TASK, "owners", "t1"),
        new Set(),
      );
    });

    it("answers the rows it dropped and the rows whose sets it changed as written", () => {
      const written = Deltas.apply(hashedDrop(TASK, ["t1"]));

      assert.deepEqual(written, new Set([`${TASK} t1`, `${PROJECT} p1`]));
    });

    it("answers the row whose inverse set it changed as written", () => {
      const written = Deltas.apply(hashedDrop(PROJECT, ["p1"]));

      assert.deepEqual(
        written,
        new Set([`${PROJECT} p1`, `${TASK} t1`, `${TASK} t2`]),
      );
    });

    // A page's rows are never stored, so the change to one's set isn't written.
    it("answers no row a page carried whose set it changed as written", () => {
      LocalDatabase.markCarried(PROJECT, "p1");

      const written = Deltas.apply(hashedDrop(TASK, ["t1"]));

      assert.deepEqual(written, new Set([`${TASK} t1`]));
      assert.deepEqual(
        LocalDatabase.getTargetIds(PROJECT, "tasks", "p1"),
        new Set(["t2"]),
      );
    });

    // Every frame of one catch-up hashes under its salt, so the hashes are worked out once.
    it("drops a row a later frame of the same catch-up names", () => {
      Deltas.apply(hashedDrop(TASK, ["t9"]));
      Deltas.apply(hashedDrop(TASK, ["t2"]));

      assert.isNull(LocalDatabase.getRow(TASK, "t2"));
    });

    // A row the client's own write filed when its answer came, which nothing the stream sent
    // filed.
    it("drops a row filed after the catch-up's hashes of its type were worked out", () => {
      Deltas.apply(hashedDrop(TASK, ["t9"]));

      LocalDatabase.putRow(TASK, {done: false, id: "t3", title: "Ship copy"});

      Deltas.apply(hashedDrop(TASK, ["t3"]));

      assert.isNull(LocalDatabase.getRow(TASK, "t3"));
    });

    it("drops a row a page carried after the catch-up's hashes of its type were worked out", () => {
      Deltas.apply(hashedDrop(TASK, ["t9"]));

      Deltas.apply(
        {put_entity: {[TASK]: [{done: false, id: "t3", title: "Ship copy"}]}},
        {insertOnly: true},
      );

      Deltas.apply(hashedDrop(TASK, ["t3"]));

      assert.isNull(LocalDatabase.getRow(TASK, "t3"));
    });

    it("drops nothing for a row a frame of the same catch-up already dropped", () => {
      Deltas.apply(hashedDrop(TASK, ["t9"]));

      Deltas.apply({
        del_relationship: {
          [PROJECT]: [{id: "p1", relationship: "tasks", target_id: "t1"}],
        },
        unsync_entity: {[TASK]: ["t1"]},
      });

      const written = Deltas.apply(hashedDrop(TASK, ["t1"]));

      assert.deepEqual(written, new Set());
    });

    it("answers nothing written when it drops nothing", () => {
      const written = Deltas.apply(hashedDrop(TASK, ["t9"]));

      assert.deepEqual(written, new Set());
    });

    // A stream cut inside a batch or a catch-up can leave a pair naming a row that never arrived.
    describe("a pair naming a row it doesn't hold", () => {
      beforeEach(() => {
        LocalDatabase.addFact(PROJECT, "tasks", "p1", "t3");
      });

      it("takes the pair out of the set", () => {
        Deltas.apply(hashedDrop(TASK, ["t3"]));

        assert.deepEqual(
          LocalDatabase.baseTargetIds(PROJECT, "tasks", "p1"),
          new Set(["t1", "t2"]),
        );
      });

      // The row held here can come from a page older than its stored record.
      it("answers no row as written", () => {
        const written = Deltas.apply(hashedDrop(TASK, ["t3"]));

        assert.deepEqual(written, new Set());
      });

      it("queues the pair to be taken out of the stored set", () => {
        Deltas.apply(hashedDrop(TASK, ["t3"]));

        assert.deepEqual(LocalDatabase.takeStoredFactRemovals(), [
          {id: "p1", relationship: "tasks", targetIds: ["t3"], type: PROJECT},
        ]);
      });

      it("takes a pair filed after the catch-up's hashes of its type were worked out", () => {
        Deltas.apply(hashedDrop(TASK, ["t9"]));

        LocalDatabase.addFact(PROJECT, "tasks", "p1", "t4");

        Deltas.apply(hashedDrop(TASK, ["t4"]));

        assert.deepEqual(
          LocalDatabase.baseTargetIds(PROJECT, "tasks", "p1"),
          new Set(["t1", "t2", "t3"]),
        );
      });

      it("leaves the pair for a hash naming another id", () => {
        Deltas.apply(hashedDrop(TASK, ["t9"]));

        assert.isTrue(
          LocalDatabase.baseTargetIds(PROJECT, "tasks", "p1").has("t3"),
        );
      });
    });

    // A page's set is the fresher, so restoring leaves it, and the pair stays in the stored copy.
    describe("a pair only the stored copy of a set names", () => {
      const storedProject = {
        facts: {tasks: ["t1", "t2", "t3"]},
        id: "p1",
        row: {id: "p1", name: "Website"},
        type: PROJECT,
      };

      beforeEach(() => {
        LocalDatabase.restore([storedProject]);
      });

      it("takes the pair out of the stored set", () => {
        Deltas.apply(hashedDrop(TASK, ["t3"]));

        assert.deepEqual(LocalDatabase.takeStoredFactRemovals(), [
          {id: "p1", relationship: "tasks", targetIds: ["t3"], type: PROJECT},
        ]);
      });

      // The row held here can be older than the stored one.
      it("doesn't write the holder over its stored record", () => {
        const written = Deltas.apply(hashedDrop(TASK, ["t3"]));

        assert.deepEqual(written, new Set());
      });

      it("takes the pair out once", () => {
        Deltas.apply(hashedDrop(TASK, ["t3"]));
        Deltas.apply(hashedDrop(TASK, ["t3"]));

        assert.deepEqual(LocalDatabase.takeStoredFactRemovals(), []);
      });

      it("takes nothing out once a frame restated the set", () => {
        Deltas.apply({
          put_entity: {
            [PROJECT]: [{id: "p1", name: "Website", tasks: ["t1", "t2"]}],
          },
        });

        Deltas.apply(hashedDrop(TASK, ["t3"]));

        assert.deepEqual(LocalDatabase.takeStoredFactRemovals(), []);
      });

      // A tab that doesn't store frames never takes them, and the pair can be told again since.
      it("forgets what the frame before took out when the next one is applied", () => {
        Deltas.apply(hashedDrop(TASK, ["t3"]));
        Deltas.apply({put_entity: {[TASK]: [{id: "t3", title: "Back"}]}});

        assert.deepEqual(LocalDatabase.takeStoredFactRemovals(), []);
      });
    });

    it("walks no pairs for a hash of a row it already dropped", () => {
      Deltas.apply(hashedDrop(TASK, ["t1"]));

      const deleteFactsNaming = sinon.spy(LocalDatabase, "deleteFactsNaming");

      try {
        Deltas.apply(hashedDrop(TASK, ["t1"]));

        assert.equal(deleteFactsNaming.callCount, 0);
      } finally {
        deleteFactsNaming.restore();
      }
    });

    it("drops a row filed again after it was dropped", () => {
      Deltas.apply(hashedDrop(TASK, ["t1"]));

      Deltas.apply({
        put_entity: {[TASK]: [{done: false, id: "t1", title: "Back"}]},
      });

      Deltas.apply(hashedDrop(TASK, ["t1"]));

      assert.isNull(LocalDatabase.getRow(TASK, "t1"));
    });

    // New rules can give the model an inverse, which is a set that can name the type.
    it("reads every id again when the model was read afresh", () => {
      const heldOrNamedIds = sinon.spy(LocalDatabase, "heldOrNamedIds");

      try {
        Deltas.apply(hashedDrop(TASK, ["t9"]));
        Model.reset();
        Deltas.apply(hashedDrop(TASK, ["t8"]));

        assert.equal(heldOrNamedIds.callCount, 2);
      } finally {
        heldOrNamedIds.restore();
      }
    });

    it("doesn't read every id again when nothing was filed since", () => {
      const heldOrNamedIds = sinon.spy(LocalDatabase, "heldOrNamedIds");

      try {
        Deltas.apply(hashedDrop(TASK, ["t9"]));
        Deltas.apply(hashedDrop(TASK, ["t8"]));

        assert.equal(heldOrNamedIds.callCount, 1);
      } finally {
        heldOrNamedIds.restore();
      }
    });
  });

  describe("apply() - keep_hashed", () => {
    const SALT = "q3Vx";

    const keepList = (type, ids) => ({
      keep_hashed: {
        [type]: [
          {hashes: ids.map((id) => DropHash.hash(SALT, id)), salt: SALT},
        ],
      },
    });

    beforeEach(() => {
      Deltas.apply({
        put_entity: {
          [PROJECT]: [{id: "p1", name: "Website", tasks: ["t1", "t2"]}],
          [TASK]: [
            {done: false, id: "t1", owners: ["p1"], title: "Draft copy"},
            {done: false, id: "t2", owners: ["p1"], title: "Review copy"},
          ],
        },
      });
    });

    it("keeps the held rows of the type it lists and drops the rest", () => {
      Deltas.apply(keepList(TASK, ["t2", "t9"]));

      assert.isNull(LocalDatabase.getRow(TASK, "t1"));
      assert.isNotNull(LocalDatabase.getRow(TASK, "t2"));
    });

    it("leaves the rows of other types alone", () => {
      Deltas.apply(keepList(TASK, []));

      assert.isNotNull(LocalDatabase.getRow(PROJECT, "p1"));
    });

    it("takes a row it drops out of the sets of the rows it still holds", () => {
      Deltas.apply(keepList(TASK, ["t2"]));

      assert.deepEqual(
        LocalDatabase.getTargetIds(PROJECT, "tasks", "p1"),
        new Set(["t2"]),
      );
    });

    // The catch-up's hashes of the type were worked out before the row was filed.
    it("judges a row filed after the catch-up's hashes of its type were worked out", () => {
      Deltas.apply({
        unsync_hashed: {
          [TASK]: [{hashes: [DropHash.hash(SALT, "t9")], salt: SALT}],
        },
      });

      Deltas.apply({
        put_entity: {[TASK]: [{done: false, id: "t3", title: "Ship copy"}]},
      });

      Deltas.apply(keepList(TASK, ["t1", "t2"]));

      assert.isNull(LocalDatabase.getRow(TASK, "t3"));
    });

    it("answers the rows it dropped and the rows whose sets it changed as written", () => {
      const written = Deltas.apply(keepList(TASK, ["t2"]));

      assert.deepEqual(written, new Set([`${TASK} t1`, `${PROJECT} p1`]));
    });

    // A stream cut inside a batch or a catch-up can leave a pair naming a row that never arrived.
    describe("a pair naming a row it doesn't hold", () => {
      beforeEach(() => {
        LocalDatabase.addFact(PROJECT, "tasks", "p1", "t3");
      });

      it("takes the pair when the list leaves the row out", () => {
        Deltas.apply(keepList(TASK, ["t1", "t2"]));

        assert.deepEqual(
          LocalDatabase.baseTargetIds(PROJECT, "tasks", "p1"),
          new Set(["t1", "t2"]),
        );
      });

      it("keeps the pair when the list names the row", () => {
        Deltas.apply(keepList(TASK, ["t1", "t2", "t3"]));

        assert.deepEqual(
          LocalDatabase.baseTargetIds(PROJECT, "tasks", "p1"),
          new Set(["t1", "t2", "t3"]),
        );
      });

      it("answers no row as written", () => {
        const written = Deltas.apply(keepList(TASK, ["t1", "t2"]));

        assert.deepEqual(written, new Set());
      });

      it("queues the pair to be taken out of the stored set", () => {
        Deltas.apply(keepList(TASK, ["t1", "t2"]));

        assert.deepEqual(LocalDatabase.takeStoredFactRemovals(), [
          {id: "p1", relationship: "tasks", targetIds: ["t3"], type: PROJECT},
        ]);
      });

      it("takes a pair only the stored set names when the list leaves its row out", () => {
        LocalDatabase.deleteFact(PROJECT, "tasks", "p1", "t3");

        LocalDatabase.restore([
          {
            facts: {tasks: ["t1", "t2", "t3"]},
            id: "p1",
            row: {id: "p1", name: "Website"},
            type: PROJECT,
          },
        ]);

        Deltas.apply(keepList(TASK, ["t1", "t2"]));

        assert.deepEqual(LocalDatabase.takeStoredFactRemovals(), [
          {id: "p1", relationship: "tasks", targetIds: ["t3"], type: PROJECT},
        ]);
      });
    });
  });

  // Never sent in v1 - a row gone and a row out of reach are both told as unsync until offline
  // writes need them apart.
  describe("apply() - del_entity", () => {
    it("drops the row the way an unsync does", () => {
      Deltas.apply({
        put_entity: {[TASK]: [{done: false, id: "t1", title: "Draft copy"}]},
      });

      Deltas.apply({del_entity: {[TASK]: ["t1"]}});

      assert.isNull(LocalDatabase.getRow(TASK, "t1"));
    });
  });

  describe("apply() - add_relationship", () => {
    it("records the pair", () => {
      Deltas.apply({
        add_relationship: {
          [PROJECT]: [{id: "p1", relationship: "tasks", target_id: "t3"}],
        },
      });

      assert.deepEqual(
        LocalDatabase.getTargetIds(PROJECT, "tasks", "p1"),
        new Set(["t3"]),
      );
    });

    it("keeps the pairs the source already had", () => {
      Deltas.apply({
        put_entity: {[PROJECT]: [{id: "p1", name: "Website", tasks: ["t1"]}]},
      });

      Deltas.apply({
        add_relationship: {
          [PROJECT]: [{id: "p1", relationship: "tasks", target_id: "t3"}],
        },
      });

      assert.deepEqual(
        LocalDatabase.getTargetIds(PROJECT, "tasks", "p1"),
        new Set(["t1", "t3"]),
      );
    });
  });

  describe("apply() - del_relationship", () => {
    it("removes the pair, keeping the source's others", () => {
      Deltas.apply({
        put_entity: {
          [PROJECT]: [{id: "p1", name: "Website", tasks: ["t1", "t2"]}],
        },
      });

      Deltas.apply({
        del_relationship: {
          [PROJECT]: [{id: "p1", relationship: "tasks", target_id: "t1"}],
        },
      });

      assert.deepEqual(
        LocalDatabase.getTargetIds(PROJECT, "tasks", "p1"),
        new Set(["t2"]),
      );
    });
  });

  describe("apply() - a frame carrying several ops", () => {
    it("applies each of them", () => {
      Deltas.apply({
        put_entity: {[TASK]: [{done: false, id: "t1", title: "Draft copy"}]},
      });

      Deltas.apply({
        add_relationship: {
          [PROJECT]: [{id: "p1", relationship: "tasks", target_id: "t3"}],
        },
        patch_entity: {[TASK]: [{id: "t1", title: "Ship it"}]},
        put_entity: {[PROJECT]: [{id: "p1", name: "Website"}]},
        unsync_entity: {[TASK]: ["t9"]},
      });

      assert.equal(LocalDatabase.getRow(TASK, "t1").title, "Ship it");
      assert.equal(LocalDatabase.getRow(PROJECT, "p1").name, "Website");

      assert.deepEqual(
        LocalDatabase.getTargetIds(PROJECT, "tasks", "p1"),
        new Set(["t3"]),
      );
    });
  });

  // A row and an edge of its own can both be in one frame - a row that arrives with a pair added
  // in the same round is the ordinary case. They cannot disagree, because the server read both
  // from one round: the put states the whole target set, the edge states one pair of it, and the
  // set already reflects the pair. Applied either way round the facts land the same, which is
  // what lets the payload be grouped by op at all.
  describe("apply() - a row and an edge of its own in one frame", () => {
    const edge = {
      [PROJECT]: [{id: "p1", relationship: "tasks", target_id: "t2"}],
    };

    const rowHoldingBoth = {
      [PROJECT]: [{id: "p1", name: "Website", tasks: ["t1", "t2"]}],
    };

    const rowHoldingOne = {
      [PROJECT]: [{id: "p1", name: "Website", tasks: ["t1"]}],
    };

    const targetIds = () =>
      new Set(LocalDatabase.getTargetIds(PROJECT, "tasks", "p1"));

    it("lands the same facts whichever way round an added pair is applied", () => {
      Deltas.apply({add_relationship: edge, put_entity: rowHoldingBoth});

      const edgeFirst = targetIds();

      LocalDatabase.reset();

      Deltas.apply({put_entity: rowHoldingBoth, add_relationship: edge});

      assert.deepEqual(edgeFirst, new Set(["t1", "t2"]));
      assert.deepEqual(targetIds(), edgeFirst);
    });

    it("lands the same facts whichever way round a removed pair is applied", () => {
      Deltas.apply({del_relationship: edge, put_entity: rowHoldingOne});

      const edgeFirst = targetIds();

      LocalDatabase.reset();

      Deltas.apply({put_entity: rowHoldingOne, del_relationship: edge});

      assert.deepEqual(edgeFirst, new Set(["t1"]));
      assert.deepEqual(targetIds(), edgeFirst);
    });
  });

  // The rows a frame WROTE, which is what a pending write of this client's is matched against to
  // learn its effect is in the base now. Written rather than merely mentioned: a delta the ingest
  // passes over changes nothing, so nothing about it is in there to be found.
  describe("apply() - the rows it wrote", () => {
    it("names a row it filed", () => {
      const written = Deltas.apply({
        put_entity: {[TASK]: [{id: "t1", title: "Draft copy"}]},
      });

      assert.deepStrictEqual(written, new Set([`${TASK} t1`]));
    });

    it("names a row it patched", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "Draft copy"});

      const written = Deltas.apply({
        patch_entity: {[TASK]: [{id: "t1", title: "Ship it"}]},
      });

      assert.deepStrictEqual(written, new Set([`${TASK} t1`]));
    });

    it("names a row it deleted", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "Draft copy"});

      const written = Deltas.apply({del_entity: {[TASK]: ["t1"]}});

      assert.deepStrictEqual(written, new Set([`${TASK} t1`]));
    });

    it("names a row it unsynced", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "Draft copy"});

      const written = Deltas.apply({unsync_entity: {[TASK]: ["t1"]}});

      assert.deepStrictEqual(written, new Set([`${TASK} t1`]));
    });

    // A row this client created and its user may not read is dropped by a frame that can arrive
    // before the batch's answer, while only the pending create holds the row. Naming it lands the
    // create, so the answer files nothing.
    it("names a row it unsynced that it doesn't hold", () => {
      const written = Deltas.apply({unsync_entity: {[TASK]: ["t1"]}});

      assert.deepStrictEqual(written, new Set([`${TASK} t1`]));
    });

    // An edge names the row whose relationships changed, which is the row a batch's own edge
    // write names - so the two match up.
    it("names an edge's source row rather than its target", () => {
      const written = Deltas.apply({
        add_relationship: {
          [PROJECT]: [{id: "p1", relationship: "tasks", target_id: "t1"}],
        },
      });

      assert.deepStrictEqual(written, new Set([`${PROJECT} p1`]));
    });

    it("names an edge's source row when the pair is removed", () => {
      const written = Deltas.apply({
        del_relationship: {
          [PROJECT]: [{id: "p1", relationship: "tasks", target_id: "t1"}],
        },
      });

      assert.deepStrictEqual(written, new Set([`${PROJECT} p1`]));
    });

    it("names every row of a frame carrying several", () => {
      const written = Deltas.apply({
        put_entity: {
          [PROJECT]: [{id: "p1", name: "Board"}],
          [TASK]: [{id: "t1", title: "Draft copy"}],
        },
      });

      assert.deepStrictEqual(written, new Set([`${PROJECT} p1`, `${TASK} t1`]));
    });

    // The base is left exactly as it was, so a pending write on that row is NOT in it - and a
    // pending create told otherwise would go off the screen with nothing to put it back until the
    // answer arrived.
    it("names nothing for a patch it passed over", () => {
      const written = Deltas.apply({
        patch_entity: {[TASK]: [{id: "t9", title: "Ship it"}]},
      });

      assert.deepStrictEqual(written, new Set());
    });

    it("names nothing for a carried row it already held", () => {
      LocalDatabase.putRow(TASK, {id: "t1", title: "Draft copy"});

      const written = Deltas.apply(
        {put_entity: {[TASK]: [{id: "t1", title: "From the page"}]}},
        {insertOnly: true},
      );

      assert.deepStrictEqual(written, new Set());
    });

    it("names a carried row it filed", () => {
      const written = Deltas.apply(
        {put_entity: {[TASK]: [{id: "t1", title: "From the page"}]}},
        {insertOnly: true},
      );

      assert.deepStrictEqual(written, new Set([`${TASK} t1`]));
    });
  });

  describe("apply() - numbers above the final point", () => {
    const numbered = (created, updated, extra = {}) =>
      Object.assign(
        {
          id: "t1",
          server_created_seq: created,
          server_updated_seq: updated,
          title: "Draft copy",
        },
        extra,
      );

    it("holds a new row's numbers above the point back from the row", () => {
      LocalDatabase.raiseFinal(10);

      Deltas.apply({put_entity: {[TASK]: [numbered(12, 12)]}});

      const row = LocalDatabase.baseRow(TASK, "t1");

      assert.isNull(row.server_created_seq);
      assert.isNull(row.server_updated_seq);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {server_created_seq: 12, server_updated_seq: 12},
        own: false,
      });
    });

    it("files numbers at or below the point as they came", () => {
      LocalDatabase.raiseFinal(12);

      Deltas.apply({put_entity: {[TASK]: [numbered(11, 12)]}});

      const row = LocalDatabase.baseRow(TASK, "t1");

      assert.equal(row.server_created_seq, 11);
      assert.equal(row.server_updated_seq, 12);
      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });

    it("holds every number back while no point was told", () => {
      Deltas.apply({put_entity: {[TASK]: [numbered(1, 1)]}});

      assert.isNull(LocalDatabase.baseRow(TASK, "t1").server_created_seq);
      assert.isNotNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });

    it("keeps an updated row's previous number while a patch's waits", () => {
      LocalDatabase.raiseFinal(10);

      Deltas.apply({put_entity: {[TASK]: [numbered(5, 8)]}});

      Deltas.apply({
        patch_entity: {
          [TASK]: [{id: "t1", server_updated_seq: 12, title: "Final copy"}],
        },
      });

      const row = LocalDatabase.baseRow(TASK, "t1");

      assert.equal(row.title, "Final copy");
      assert.equal(row.server_created_seq, 5);
      assert.equal(row.server_updated_seq, 8);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {server_updated_seq: 12},
        own: false,
      });
    });

    it("keeps a held row's previous number while a put's waits", () => {
      LocalDatabase.raiseFinal(10);

      Deltas.apply({put_entity: {[TASK]: [numbered(5, 8)]}});
      Deltas.apply({put_entity: {[TASK]: [numbered(5, 15)]}});

      const row = LocalDatabase.baseRow(TASK, "t1");

      assert.equal(row.server_created_seq, 5);
      assert.equal(row.server_updated_seq, 8);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {server_updated_seq: 15},
        own: false,
      });
    });

    // A delivery sent again from an older place can bring a final number after a newer one that
    // waits.
    it("keeps a waiting number over an older one that is final", () => {
      LocalDatabase.raiseFinal(10);

      Deltas.apply({put_entity: {[TASK]: [numbered(5, 12)]}});

      Deltas.apply({
        patch_entity: {[TASK]: [{id: "t1", server_updated_seq: 8}]},
      });

      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_updated_seq, 8);

      LocalDatabase.raiseFinal(12);

      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_updated_seq, 12);
    });

    it("keeps the own flag beside the row while its created number waits", () => {
      LocalDatabase.raiseFinal(10);

      Deltas.apply({put_entity: {[TASK]: [numbered(12, 12, {$own: true})]}});

      assert.notProperty(LocalDatabase.baseRow(TASK, "t1"), "$own");
      assert.isTrue(LocalDatabase.waitingNumbers(TASK, "t1").own);
    });

    it("keeps the own flag through a later put that doesn't carry it", () => {
      LocalDatabase.raiseFinal(10);

      Deltas.apply({put_entity: {[TASK]: [numbered(12, 12, {$own: true})]}});
      Deltas.apply({put_entity: {[TASK]: [numbered(12, 14)]}});

      assert.isTrue(LocalDatabase.waitingNumbers(TASK, "t1").own);
    });

    it("drops the own flag of a row whose created number is final", () => {
      LocalDatabase.raiseFinal(12);

      Deltas.apply({put_entity: {[TASK]: [numbered(11, 14, {$own: true})]}});

      assert.notProperty(LocalDatabase.baseRow(TASK, "t1"), "$own");

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {server_updated_seq: 14},
        own: false,
      });
    });

    it("keeps a carried row's numbers above the point beside it as shown", () => {
      LocalDatabase.raiseFinal(10);

      Deltas.apply(
        {put_entity: {[TASK]: [numbered(12, 14)]}},
        {insertOnly: true},
      );

      const row = LocalDatabase.baseRow(TASK, "t1");

      assert.isNull(row.server_created_seq);
      assert.isNull(row.server_updated_seq);
      assert.deepEqual(LocalDatabase.carriedEntries(), [[TASK, "t1"]]);

      assert.deepStrictEqual(LocalDatabase.waitingNumbers(TASK, "t1"), {
        numbers: {},
        own: false,
        shown: {server_created_seq: 12, server_updated_seq: 14},
      });
    });

    it("files a carried row's numbers at or below the point as they came", () => {
      LocalDatabase.raiseFinal(12);

      Deltas.apply(
        {put_entity: {[TASK]: [numbered(11, 12)]}},
        {insertOnly: true},
      );

      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_created_seq, 11);
      assert.equal(LocalDatabase.baseRow(TASK, "t1").server_updated_seq, 12);
      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });

    // The held row's values aren't the page's version, so the page's numbers aren't its own.
    it("takes no carried number for a row it holds, writing nothing", () => {
      LocalDatabase.raiseFinal(10);

      Deltas.apply({put_entity: {[TASK]: [numbered(5, 8)]}});

      const written = Deltas.apply(
        {put_entity: {[TASK]: [numbered(5, 14, {title: "Final copy"})]}},
        {insertOnly: true},
      );

      assert.deepEqual(written, new Set());

      const row = LocalDatabase.baseRow(TASK, "t1");

      assert.equal(row.title, "Draft copy");
      assert.equal(row.server_updated_seq, 8);
      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });

    it("holds nothing for a patch naming a row it doesn't hold", () => {
      LocalDatabase.raiseFinal(10);

      Deltas.apply({
        patch_entity: {[TASK]: [{id: "t1", server_updated_seq: 12}]},
      });

      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });

    it("forgets a row's waiting numbers when the row goes", () => {
      LocalDatabase.raiseFinal(10);

      Deltas.apply({put_entity: {[TASK]: [numbered(12, 12)]}});
      Deltas.apply({unsync_entity: {[TASK]: ["t1"]}});

      LocalDatabase.raiseFinal(20);

      assert.isNull(LocalDatabase.baseRow(TASK, "t1"));
      assert.isNull(LocalDatabase.waitingNumbers(TASK, "t1"));
    });
  });

  describe("apply() - an op this build does not know", () => {
    it("raises rather than passing it over", () => {
      assert.throw(
        () => Deltas.apply({rename_entity: {[TASK]: [{id: "t1"}]}}),
        HologramRuntimeError,
        "unknown sync delta op: rename_entity",
      );
    });
  });
});
