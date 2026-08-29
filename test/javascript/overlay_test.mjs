"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import Batch from "../../assets/js/batch.mjs";
import Clock from "../../assets/js/clock.mjs";
import Model from "../../assets/js/model.mjs";
import Overlay from "../../assets/js/overlay.mjs";

defineRuntimeGlobals();

describe("Overlay", () => {
  const TODO = "MyApp.Todo";

  // The instant every stamp below is taken at, so an expected timestamp is a value rather than
  // whatever the machine's clock read.
  const nowMs = 1_756_100_000_123;
  const stamp = nowMs * 1024;
  const timestamp = "2025-08-25T05:33:20.123000Z";

  beforeEach(() => {
    globalThis.Hologram.sync = {
      model: {
        [TODO]: {
          attributes: {
            created_at: "datetime",
            done: "boolean",
            id: "uuid",
            title: "string",
            updated_at: "datetime",
            votes: "integer",
          },
          constraints: {},
          defaults: {},
          enumValues: {},
          frameworkAttributes: [],
          relationships: {
            project: {optional: true, toMany: false, type: "MyApp.Project"},
          },
          serverOnly: [],
        },
      },
    };

    Clock.reset();
    Model.reset();
    Overlay.reset();
  });

  // Mocha runs every suite in one process and the overlay is module state, so a batch left pushed
  // here would fold itself into another file's reads.
  afterEach(() => {
    Overlay.reset();
  });

  const base = (overrides = {}) =>
    Object.assign(
      {
        created_at: "2026-01-01T00:00:00.000000Z",
        done: false,
        id: "t1",
        project_id: "p1",
        title: "Draft copy",
        title_sort: "draft copy",
        updated_at: "2026-01-01T00:00:00.000000Z",
        votes: 3,
        $revisions: {done: 10, project_id: 10, title: 10, votes: 10},
      },
      overrides,
    );

  const createWrite = (overrides = {}) =>
    Object.assign(
      {
        data: {done: false, project_id: "p1", title: "Łódź", votes: 0},
        id: "t1",
        op: "create",
        stamp,
        type: TODO,
      },
      overrides,
    );

  const updateWrite = (overrides = {}) =>
    Object.assign({id: "t1", op: "update", stamp, type: TODO}, overrides);

  const pushed = (...writes) => {
    const batch = new Batch("todos");

    for (const write of writes) {
      batch.append(write);
    }

    Overlay.push(batch);

    return batch;
  };

  describe("durability()", () => {
    it("reads a row no pending write names as confirmed", () => {
      assert.equal(Overlay.durability(TODO, "t1"), "confirmed");
    });

    it("reads a row a pending write names as applied", () => {
      pushed(createWrite());

      assert.equal(Overlay.durability(TODO, "t1"), "applied");
    });
  });

  describe("foldRow()", () => {
    it("answers the base itself when no pending write names the row", () => {
      const row = base();

      assert.strictEqual(Overlay.foldRow(TODO, "t1", row), row);
    });

    it("builds the row a create will store", () => {
      pushed(createWrite());

      assert.deepStrictEqual(Overlay.foldRow(TODO, "t1", null), {
        created_at: timestamp,
        done: false,
        id: "t1",
        project_id: "p1",
        title: "Łódź",
        title_sort: "lodz",
        updated_at: timestamp,
        votes: 0,
        $revisions: {
          done: stamp,
          project_id: stamp,
          title: stamp,
          votes: stamp,
        },
      });
    });

    it("timestamps a create from the moment its writer made it", () => {
      const daysAgo = (nowMs - 2 * 86_400_000) * 1024;

      pushed(createWrite({stamp: daysAgo}));

      const row = Overlay.foldRow(TODO, "t1", null);

      assert.equal(row.created_at, "2025-08-23T05:33:20.123000Z");
      assert.equal(row.created_at, row.updated_at);
    });

    // Nothing but this client writes an id this client minted, so a base row under one can only be
    // the frame confirming this create. The server's copy is the better one - it carries whatever
    // the server settled beyond what the write named - so it is what stands.
    it("answers the base row the confirming frame delivered first", () => {
      pushed(createWrite());

      const row = base({title: "From the frame"});

      assert.strictEqual(Overlay.foldRow(TODO, "t1", row), row);
    });

    it("writes the values an update names over the base", () => {
      pushed(updateWrite({data: {title: "Ship it"}}));

      const row = Overlay.foldRow(TODO, "t1", base());

      assert.equal(row.title, "Ship it");
      assert.equal(row.title_sort, "ship it");
      assert.isFalse(row.done);
    });

    it("takes the revision of every field an update names, and leaves the rest", () => {
      pushed(updateWrite({data: {title: "Ship it"}}));

      assert.deepStrictEqual(Overlay.foldRow(TODO, "t1", base()).$revisions, {
        done: 10,
        project_id: 10,
        title: stamp,
        votes: 10,
      });
    });

    it("leaves a column the base has moved past the write's stamp", () => {
      pushed(updateWrite({data: {title: "Ship it"}}));

      const row = Overlay.foldRow(
        TODO,
        "t1",
        base({
          $revisions: {done: 10, project_id: 10, title: stamp + 1, votes: 10},
        }),
      );

      assert.equal(row.title, "Draft copy");
      assert.equal(row.$revisions.title, stamp + 1);
    });

    it("applies the columns that still win and leaves the ones that lost, within one write", () => {
      pushed(updateWrite({data: {done: true, title: "Ship it"}}));

      const row = Overlay.foldRow(
        TODO,
        "t1",
        base({
          $revisions: {done: 10, project_id: 10, title: stamp + 1, votes: 10},
        }),
      );

      assert.isTrue(row.done);
      assert.equal(row.$revisions.done, stamp);
      assert.equal(row.title, "Draft copy");
      assert.equal(row.$revisions.title, stamp + 1);
    });

    // The server stores a client's stamp verbatim for a value it accepts, so a revision equal to
    // the write's own stamp says the write is already in the base - and applying it again is
    // work with no effect, which is why the base comes back as it stands.
    it("reads its own landed value as the base", () => {
      pushed(updateWrite({data: {title: "Ship it"}}));

      const row = base({
        title: "Ship it",
        title_sort: "ship it",
        $revisions: {done: 10, project_id: 10, title: stamp, votes: 10},
      });

      assert.strictEqual(Overlay.foldRow(TODO, "t1", row), row);
    });

    it("leaves updated_at alone when every column of the write has lost", () => {
      pushed(updateWrite({data: {title: "Ship it"}}));

      const row = Overlay.foldRow(
        TODO,
        "t1",
        base({
          $revisions: {done: 10, project_id: 10, title: stamp + 1, votes: 10},
        }),
      );

      assert.equal(row.updated_at, "2026-01-01T00:00:00.000000Z");
    });

    it("moves a counter by the delta and leaves its revision alone", () => {
      pushed(updateWrite({deltas: {votes: 2}}));

      const row = Overlay.foldRow(TODO, "t1", base());

      assert.equal(row.votes, 5);
      assert.equal(row.$revisions.votes, 10);
    });

    // A move is not a claim about the value, so there is nothing for it to lose and no revision to
    // judge it by. What keeps a move that has already landed from counting twice is the batch's
    // landed set - the server advances a contended counter's revision by one rather than to the
    // mover's stamp, so the revision cannot answer that question at all.
    it("moves a counter whatever revision the base holds for it", () => {
      pushed(updateWrite({deltas: {votes: 2}}));

      const row = Overlay.foldRow(
        TODO,
        "t1",
        base({
          votes: 5,
          $revisions: {done: 10, project_id: 10, title: 10, votes: stamp + 1},
        }),
      );

      assert.equal(row.votes, 7);
    });

    it("stamps an update's updated_at from the write", () => {
      pushed(updateWrite({data: {title: "Ship it"}}));

      assert.equal(Overlay.foldRow(TODO, "t1", base()).updated_at, timestamp);
    });

    it("leaves the base object untouched", () => {
      const row = base();

      pushed(updateWrite({data: {title: "Ship it"}}));
      Overlay.foldRow(TODO, "t1", row);

      assert.equal(row.title, "Draft copy");
      assert.equal(row.$revisions.title, 10);
    });

    it("answers nothing for an update onto a row that is gone", () => {
      pushed(updateWrite({data: {title: "Ship it"}}));

      assert.isNull(Overlay.foldRow(TODO, "t1", null));
    });

    it("answers nothing for a delete of a row nothing moved past the stamp", () => {
      pushed({id: "t1", op: "delete", stamp, type: TODO});

      assert.isNull(Overlay.foldRow(TODO, "t1", base()));
    });

    // One column is enough: a delete is a claim about every column at once, so a newer edit to any
    // of them is a newer edit than the delete, and the server will keep the row.
    it("keeps a row a newer edit moved past the delete's stamp", () => {
      pushed({id: "t1", op: "delete", stamp, type: TODO});

      const row = base({
        $revisions: {done: 10, project_id: 10, title: stamp + 1, votes: 10},
      });

      assert.strictEqual(Overlay.foldRow(TODO, "t1", row), row);
    });

    it("answers nothing for a delete of a row holding no revisions", () => {
      pushed({id: "t1", op: "delete", stamp, type: TODO});

      assert.isNull(Overlay.foldRow(TODO, "t1", base({$revisions: {}})));
    });

    it("leaves the row as it was for an edge, which changes no column", () => {
      pushed({
        id: "t1",
        op: "add_relationship",
        relationship: "tags",
        target_id: "g1",
        type: TODO,
      });

      assert.deepStrictEqual(Overlay.foldRow(TODO, "t1", base()), base());
    });

    it("stacks the batches in the order they were made", () => {
      pushed(updateWrite({data: {title: "Second"}}));
      pushed(updateWrite({data: {title: "Third"}, stamp: stamp + 1}));

      const row = Overlay.foldRow(TODO, "t1", base());

      assert.equal(row.title, "Third");
      assert.equal(row.$revisions.title, stamp + 1);
    });

    it("stacks the writes of one batch in the order they were made", () => {
      pushed(
        updateWrite({data: {title: "Second"}}),
        updateWrite({data: {title: "Third"}, stamp: stamp + 1}),
      );

      assert.equal(Overlay.foldRow(TODO, "t1", base()).title, "Third");
    });

    // The guard test below never reaches the write walk - it returns at names() - so this is the
    // one that pins that the walk itself filters by id.
    it("applies only the writes naming the row, when its batch names others too", () => {
      pushed(
        updateWrite({data: {title: "Mine"}}),
        createWrite({id: "t2", data: {title: "Not mine", votes: 0}}),
      );

      const row = Overlay.foldRow(TODO, "t1", base());

      assert.equal(row.id, "t1");
      assert.equal(row.title, "Mine");
    });

    it("passes over a pending write naming another row of the same type", () => {
      pushed(updateWrite({data: {title: "Ship it"}, id: "t2"}));

      const row = base();

      assert.strictEqual(Overlay.foldRow(TODO, "t1", row), row);
    });
  });

  describe("foldTable()", () => {
    const table = (...rows) =>
      Object.fromEntries(rows.map((row) => [row.id, row]));

    it("answers the base itself when no pending write names the type", () => {
      const held = table(base());

      assert.strictEqual(Overlay.foldTable(TODO, held), held);
    });

    it("answers the base itself when the pending writes name another type", () => {
      pushed(createWrite({type: "MyApp.Other"}));

      const held = table(base());

      assert.strictEqual(Overlay.foldTable(TODO, held), held);
    });

    it("puts a created row in the table", () => {
      pushed(createWrite({id: "t2"}));

      const folded = Overlay.foldTable(TODO, table(base()));

      assert.deepStrictEqual(Object.keys(folded).sort(), ["t1", "t2"]);
      assert.equal(folded.t2.title, "Łódź");
    });

    it("takes a deleted row out of the table", () => {
      pushed({id: "t1", op: "delete", stamp, type: TODO});

      assert.deepStrictEqual(Overlay.foldTable(TODO, table(base())), {});
    });

    it("keeps a deleted row a newer edit moved past", () => {
      pushed({id: "t1", op: "delete", stamp, type: TODO});

      const row = base({
        $revisions: {done: 10, project_id: 10, title: stamp + 1, votes: 10},
      });

      assert.deepStrictEqual(Object.keys(Overlay.foldTable(TODO, table(row))), [
        "t1",
      ]);
    });

    it("passes over a delete of a row the table does not hold", () => {
      pushed({id: "t9", op: "delete", stamp, type: TODO});

      assert.deepStrictEqual(
        Object.keys(Overlay.foldTable(TODO, table(base()))),
        ["t1"],
      );
    });

    it("shows an updated row as its writer left it", () => {
      pushed(updateWrite({data: {title: "Ship it"}}));

      assert.equal(Overlay.foldTable(TODO, table(base())).t1.title, "Ship it");
    });

    it("leaves the base table and its rows untouched", () => {
      const row = base();
      const held = table(row);

      pushed(updateWrite({data: {title: "Ship it"}}));
      pushed(createWrite({id: "t2"}));
      Overlay.foldTable(TODO, held);

      assert.deepStrictEqual(Object.keys(held), ["t1"]);
      assert.equal(row.title, "Draft copy");
    });

    it("reads a write appended after an earlier fold, so an action reads its own writes", () => {
      const held = table(base());
      const batch = pushed(updateWrite({data: {title: "First"}}));

      assert.equal(Overlay.foldTable(TODO, held).t1.title, "First");

      batch.append(updateWrite({data: {title: "Second"}, stamp: stamp + 1}));

      assert.equal(Overlay.foldTable(TODO, held).t1.title, "Second");
    });
  });

  describe("foldTargetIds()", () => {
    const addEdge = (overrides = {}) =>
      Object.assign(
        {
          id: "t1",
          op: "add_relationship",
          relationship: "tags",
          target_id: "g2",
          type: TODO,
        },
        overrides,
      );

    it("answers the base itself when no pending write names the row", () => {
      const held = new Set(["g1"]);

      assert.strictEqual(Overlay.foldTargetIds(TODO, "tags", "t1", held), held);
    });

    it("adds the target an edge names", () => {
      pushed(addEdge());

      assert.deepStrictEqual(
        Overlay.foldTargetIds(TODO, "tags", "t1", new Set(["g1"])),
        new Set(["g1", "g2"]),
      );
    });

    it("removes the target a deleted edge names", () => {
      pushed(addEdge({op: "delete_relationship", target_id: "g1"}));

      assert.deepStrictEqual(
        Overlay.foldTargetIds(TODO, "tags", "t1", new Set(["g1", "g2"])),
        new Set(["g2"]),
      );
    });

    it("passes over an edge of another relationship", () => {
      pushed(addEdge({relationship: "labels"}));

      assert.deepStrictEqual(
        Overlay.foldTargetIds(TODO, "tags", "t1", new Set(["g1"])),
        new Set(["g1"]),
      );
    });

    it("empties the set when the source row is deleted", () => {
      pushed({id: "t1", op: "delete", stamp, type: TODO});

      assert.deepStrictEqual(
        Overlay.foldTargetIds(TODO, "tags", "t1", new Set(["g1"])),
        new Set(),
      );
    });

    it("applies only the edges naming the row, when its batch names others too", () => {
      pushed(addEdge(), addEdge({id: "t2", target_id: "g9"}));

      assert.deepStrictEqual(
        Overlay.foldTargetIds(TODO, "tags", "t1", new Set(["g1"])),
        new Set(["g1", "g2"]),
      );
    });

    it("passes over an edge whose source is another row", () => {
      pushed(addEdge({id: "t2"}));

      const held = new Set(["g1"]);

      assert.strictEqual(Overlay.foldTargetIds(TODO, "tags", "t1", held), held);
    });

    it("leaves the base set untouched", () => {
      const held = new Set(["g1"]);

      pushed(addEdge());
      Overlay.foldTargetIds(TODO, "tags", "t1", held);

      assert.deepStrictEqual(held, new Set(["g1"]));
    });
  });

  describe("names()", () => {
    it("answers for the rows a batch's writes name, and no others", () => {
      pushed(createWrite());

      assert.isTrue(Overlay.names(TODO, "t1"));
      assert.isFalse(Overlay.names(TODO, "t2"));
      assert.isFalse(Overlay.names("MyApp.Other", "t1"));
    });
  });

  describe("remove()", () => {
    it("takes the batch's writes out of the fold", () => {
      const batch = pushed(createWrite());

      Overlay.remove(batch);

      assert.isNull(Overlay.foldRow(TODO, "t1", null));
      assert.isFalse(Overlay.names(TODO, "t1"));
    });

    it("leaves the batches it was not given", () => {
      const batch = pushed(updateWrite({data: {title: "Second"}}));
      pushed(updateWrite({data: {title: "Third"}, stamp: stamp + 1}));

      Overlay.remove(batch);

      assert.equal(Overlay.foldRow(TODO, "t1", base()).title, "Third");
    });
  });

  describe("reset()", () => {
    it("drops every batch", () => {
      pushed(createWrite());

      Overlay.reset();

      assert.isFalse(Overlay.names(TODO, "t1"));
    });
  });
});
