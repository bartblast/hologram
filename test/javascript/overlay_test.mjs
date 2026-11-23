"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import Batch from "../../assets/js/batch.mjs";
import Clock from "../../assets/js/clock.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Model from "../../assets/js/model.mjs";
import Overlay from "../../assets/js/overlay.mjs";
import Type from "../../assets/js/type.mjs";

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
        server_created_at: "2026-01-01T00:00:01.000000Z",
        server_updated_at: "2026-01-01T00:00:02.000000Z",
        title: "Draft copy",
        title$sort: "draft copy",
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
        server_created_at: null,
        server_updated_at: null,
        title: "Łódź",
        title$sort: "lodz",
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

    it("gives a created job the defaults of the framework's attributes", () => {
      const JOB = "MyApp.Jobs.Notify";

      globalThis.Hologram.sync.model[JOB] = {
        attributes: {
          actor_id: "uuid",
          attempt: "integer",
          created_at: "datetime",
          error: "string",
          id: "uuid",
          scheduled_at: "datetime",
          status: "enum",
          updated_at: "datetime",
        },
        constraints: {},
        defaults: {attempt: Type.integer(0), status: Type.atom("queued")},
        enumValues: {status: ["queued", "running", "done", "failed"]},
        frameworkAttributes: [
          "actor_id",
          "attempt",
          "error",
          "scheduled_at",
          "status",
        ],
        relationships: {},
        serverOnly: ["error"],
      };

      Model.reset();

      pushed(createWrite({data: {}, id: "j1", type: JOB}));

      const row = Overlay.foldRow(JOB, "j1", null);

      assert.strictEqual(row.attempt, 0);
      assert.strictEqual(row.status, "queued");
      assert.notProperty(row, "scheduled_at");
      assert.notProperty(row.$revisions, "attempt");
    });

    it("timestamps a create from the moment its writer made it", () => {
      const daysAgo = (nowMs - 2 * 86_400_000) * 1024;

      pushed(createWrite({stamp: daysAgo}));

      const row = Overlay.foldRow(TODO, "t1", null);

      assert.equal(row.created_at, "2025-08-23T05:33:20.123000Z");
      assert.equal(row.created_at, row.updated_at);
    });

    // The server's pair is when the row reaches the server, which a pending update has not - so
    // the row keeps the times the server last gave it until its own row says otherwise.
    it("leaves the server's pair of the base under a pending update", () => {
      pushed(updateWrite({data: {title: "Ship it"}}));

      const row = Overlay.foldRow(TODO, "t1", base());

      assert.equal(row.server_created_at, "2026-01-01T00:00:01.000000Z");
      assert.equal(row.server_updated_at, "2026-01-01T00:00:02.000000Z");
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
      assert.equal(row.title$sort, "ship it");
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
        title$sort: "ship it",
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

    it("moves a counter across what a Number holds exactly", () => {
      pushed(updateWrite({deltas: {votes: 2}}));

      const row = Overlay.foldRow(TODO, "t1", base({votes: 9007199254740991}));

      assert.strictEqual(row.votes, 9007199254740993n);
    });

    it("moves a big counter back to a Number once a Number holds it", () => {
      pushed(updateWrite({deltas: {votes: -2}}));

      const row = Overlay.foldRow(TODO, "t1", base({votes: 9007199254740993n}));

      assert.strictEqual(row.votes, 9007199254740991);
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

    // The frame carrying this write has already been applied, so the base holds its effect as the
    // server resolved it - folding it on top again would add the same move a second time.
    it("passes over a write whose frame has already arrived", () => {
      const batch = pushed(updateWrite({deltas: {votes: 2}}));
      batch.land(new Set([`${TODO} t1`]));

      const row = base({votes: 5});

      assert.strictEqual(Overlay.foldRow(TODO, "t1", row), row);
    });

    // A batch's writes can reach two windows and come back as two frames, so one of its rows can
    // be in the base while the other is still only this client's.
    it("applies a write on a row no frame has carried, beside one that has", () => {
      const batch = pushed(
        updateWrite({data: {title: "Landed"}}),
        updateWrite({data: {title: "Still mine"}, id: "t2"}),
      );

      batch.land(new Set([`${TODO} t1`]));

      const landedRow = base();
      const pendingRow = base({id: "t2"});

      assert.strictEqual(Overlay.foldRow(TODO, "t1", landedRow), landedRow);
      assert.equal(Overlay.foldRow(TODO, "t2", pendingRow).title, "Still mine");
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

    it("passes over a write whose frame has already arrived", () => {
      const batch = pushed(updateWrite({data: {title: "Mine"}}));
      batch.land(new Set([`${TODO} t1`]));

      const held = base();

      assert.strictEqual(Overlay.foldTable(TODO, table(held))[held.id], held);
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

    it("passes over an edge whose frame has already arrived", () => {
      const batch = pushed({
        id: "t1",
        op: "add_relationship",
        relationship: "tags",
        target_id: "g2",
        type: TODO,
      });

      batch.land(new Set([`${TODO} t1`]));

      assert.deepStrictEqual(
        Overlay.foldTargetIds(TODO, "tags", "t1", new Set(["g1"])),
        new Set(["g1"]),
      );
    });

    it("leaves the base set untouched", () => {
      const held = new Set(["g1"]);

      pushed(addEdge());
      Overlay.foldTargetIds(TODO, "tags", "t1", held);

      assert.deepStrictEqual(held, new Set(["g1"]));
    });
  });

  describe("foldTargetIds() of an inverse of a to-many", () => {
    const LABEL = "MyApp.Label";

    beforeEach(() => {
      globalThis.Hologram.sync.model[TODO].relationships.labels = {
        optional: false,
        toMany: true,
        type: LABEL,
      };

      globalThis.Hologram.sync.model[LABEL] = {
        attributes: {id: "uuid", name: "string"},
        constraints: {},
        defaults: {},
        enumValues: {},
        frameworkAttributes: [],
        inverses: {
          todos: {
            forward: "labels",
            reference: false,
            sort: [],
            toMany: true,
            type: TODO,
          },
        },
        relationships: {},
        serverOnly: [],
      };

      Model.reset();
    });

    const labelEdge = (overrides = {}) =>
      Object.assign(
        {
          id: "t1",
          op: "add_relationship",
          relationship: "labels",
          target_id: "l1",
          type: TODO,
        },
        overrides,
      );

    it("answers the base itself when no pending write is of the related type", () => {
      const held = new Set(["t2"]);

      assert.strictEqual(
        Overlay.foldTargetIds(LABEL, "todos", "l1", held),
        held,
      );
    });

    it("adds the related row a pending edge to the row comes from", () => {
      pushed(labelEdge());

      assert.deepStrictEqual(
        Overlay.foldTargetIds(LABEL, "todos", "l1", new Set(["t2"])),
        new Set(["t1", "t2"]),
      );
    });

    it("removes the related row a pending deleted edge comes from", () => {
      pushed(labelEdge({op: "delete_relationship"}));

      assert.deepStrictEqual(
        Overlay.foldTargetIds(LABEL, "todos", "l1", new Set(["t1", "t2"])),
        new Set(["t2"]),
      );
    });

    it("removes a related row a pending delete takes away", () => {
      pushed(updateWrite({id: "t2", op: "delete"}));

      assert.deepStrictEqual(
        Overlay.foldTargetIds(LABEL, "todos", "l1", new Set(["t1", "t2"])),
        new Set(["t1"]),
      );
    });

    it("passes over a pending edge to another row", () => {
      pushed(labelEdge({id: "t3", target_id: "l2"}), labelEdge());

      assert.deepStrictEqual(
        Overlay.foldTargetIds(LABEL, "todos", "l1", new Set(["t2"])),
        new Set(["t1", "t2"]),
      );
    });

    it("passes over an edge whose frame has already arrived", () => {
      const batch = pushed(labelEdge());

      batch.land(new Set([`${TODO} t1`]));

      assert.deepStrictEqual(
        Overlay.foldTargetIds(LABEL, "todos", "l1", new Set(["t2"])),
        new Set(["t2"]),
      );
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

  describe("promote()", () => {
    beforeEach(() => {
      LocalDatabase.reset();
    });

    afterEach(() => {
      LocalDatabase.reset();
    });

    describe("a delete the answer kept the row of", () => {
      it("leaves the row standing when its revisions are below the delete's stamp", () => {
        const row = base();

        LocalDatabase.putRow(TODO, row);

        const batch = pushed({id: "t1", op: "delete", stamp, type: TODO});

        Overlay.promote(batch, {0: row});

        assert.deepEqual(LocalDatabase.baseRow(TODO, "t1"), row);
        assert.isFalse(Overlay.names(TODO, "t1"));
      });
    });

    describe("a write the answer withholds", () => {
      const withheld = {0: {$withheld: true}};

      it("leaves a held row standing under a delete", () => {
        const row = base();

        LocalDatabase.putRow(TODO, row);

        const batch = pushed({id: "t1", op: "delete", stamp, type: TODO});

        Overlay.promote(batch, withheld);

        assert.deepEqual(LocalDatabase.baseRow(TODO, "t1"), row);
        assert.isFalse(Overlay.names(TODO, "t1"));
      });

      it("files nothing, leaves a held row alone and takes the layer away", () => {
        const held = base({id: "t2", title: "Held", title$sort: "held"});

        LocalDatabase.putRow(TODO, held);

        const batch = pushed(createWrite(), createWrite({id: "t2"}));

        Overlay.promote(batch, {0: {$withheld: true}, 1: {$withheld: true}});

        assert.isNull(LocalDatabase.baseRow(TODO, "t1"));
        assert.deepEqual(LocalDatabase.baseRow(TODO, "t2"), held);
        assert.isFalse(Overlay.names(TODO, "t1"));
      });

      it("records nothing for a pending fill", () => {
        const batch = pushed(createWrite());

        batch.seal(3);

        Overlay.promote(batch, withheld, {fillPending: true});

        assert.deepEqual(LocalDatabase.carriedEntries(), []);
      });

      it("still promotes the batch's other writes", () => {
        const batch = pushed(createWrite(), createWrite({id: "t2"}));

        Overlay.promote(batch, withheld);

        assert.isNull(LocalDatabase.baseRow(TODO, "t1"));
        assert.isNotNull(LocalDatabase.baseRow(TODO, "t2"));
      });
    });

    describe("while a fill is pending", () => {
      const sealedCreate = (seq, overrides = {}) => {
        const batch = pushed(createWrite(overrides));

        batch.seal(seq);

        return batch;
      };

      it("leaves a filed create for its type's marker to judge", () => {
        Overlay.promote(sealedCreate(3), {}, {fillPending: true});

        assert.deepEqual(LocalDatabase.carriedEntries(), [[TODO, "t1"]]);

        LocalDatabase.markTypesSynced([TODO], 3);

        assert.isNull(LocalDatabase.baseRow(TODO, "t1"));
      });

      it("records the batch's number with the row", () => {
        Overlay.promote(sealedCreate(4), {}, {fillPending: true});

        LocalDatabase.markTypesSynced([TODO], 3);

        assert.isNotNull(LocalDatabase.baseRow(TODO, "t1"));
      });

      // A role grant made twice is answered with the stored row, which the answer files itself.
      it("leaves a create the answer filed whole for its marker", () => {
        const kept = {0: base({$revisions: {}, title: "stored"})};

        Overlay.promote(sealedCreate(3), kept, {fillPending: true});

        assert.deepEqual(LocalDatabase.carriedEntries(), [[TODO, "t1"]]);
      });

      it("doesn't record a create over a row the base holds", () => {
        LocalDatabase.putRow(TODO, base());
        LocalDatabase.markCarried(TODO, "t1");

        Overlay.promote(sealedCreate(4), {}, {fillPending: true});
        LocalDatabase.markTypesSynced([TODO], 3);

        assert.isNull(LocalDatabase.baseRow(TODO, "t1"));
      });

      // Past its marker, a batch the fill read was landed, so this one committed after the read and
      // its session has yet to judge it. Nothing may store the row until then.
      it("keeps a create answered after its type's marker carried until the fill ends", () => {
        LocalDatabase.markTypesSynced([TODO], 3);

        Overlay.promote(sealedCreate(4), {}, {fillPending: true});

        assert.isNotNull(LocalDatabase.baseRow(TODO, "t1"));
        assert.deepEqual(LocalDatabase.carriedEntries(), [[TODO, "t1"]]);

        LocalDatabase.markAllSynced();

        assert.isNotNull(LocalDatabase.baseRow(TODO, "t1"));
        assert.deepEqual(LocalDatabase.carriedEntries(), []);
      });

      it("doesn't record a landed create", () => {
        const batch = sealedCreate(3);

        batch.land(new Set([`${TODO} t1`]));

        Overlay.promote(batch, {}, {fillPending: true});

        assert.isNull(LocalDatabase.baseRow(TODO, "t1"));
        assert.deepEqual(LocalDatabase.carriedEntries(), []);
      });

      it("doesn't record a write that isn't a create", () => {
        LocalDatabase.putRow(TODO, base());

        const batch = pushed(updateWrite({data: {title: "changed"}}));

        batch.seal(3);

        Overlay.promote(batch, {}, {fillPending: true});

        assert.deepEqual(LocalDatabase.carriedEntries(), []);
      });
    });

    // A client coming back holds a place, and its session judges the batches it missed.
    it("doesn't leave a filed create for a marker when no fill is pending", () => {
      const batch = pushed(createWrite());

      batch.seal(3);

      Overlay.promote(batch, {});

      assert.isNotNull(LocalDatabase.baseRow(TODO, "t1"));
      assert.deepEqual(LocalDatabase.carriedEntries(), []);
    });

    // The frame carrying this write has already been applied, so the base holds the row as the
    // server left it. Folding the write in again would add the move a second time and write that
    // number down for good - no later frame corrects it, because the server has nothing new to
    // say about a row nothing has touched since.
    it("does not promote a write whose frame has already arrived", () => {
      LocalDatabase.putRow(TODO, base({votes: 5}));

      const batch = pushed(updateWrite({deltas: {votes: 2}}));
      batch.land(new Set([`${TODO} t1`]));

      Overlay.promote(batch, {});

      assert.equal(LocalDatabase.baseRow(TODO, "t1").votes, 5);
    });

    it("leaves a column that lost with no value sent back as the base holds it", () => {
      LocalDatabase.putRow(TODO, base({title: "stored"}));

      const batch = pushed(updateWrite({data: {title: "refused"}}));

      Overlay.promote(batch, {}, {dropped: {0: {title: "refused"}}});

      assert.equal(LocalDatabase.baseRow(TODO, "t1").title, "stored");
    });

    it("still promotes the columns of the write that weren't dropped", () => {
      LocalDatabase.putRow(TODO, base({title: "stored", votes: 1}));

      const batch = pushed(updateWrite({data: {title: "refused", votes: 2}}));

      Overlay.promote(batch, {}, {dropped: {0: {title: "refused"}}});

      const row = LocalDatabase.baseRow(TODO, "t1");

      assert.equal(row.title, "stored");
      assert.equal(row.votes, 2);
    });

    it("leaves out a dropped column named like an inherited property", () => {
      LocalDatabase.putRow(
        TODO,
        base({$revisions: {constructor: 1}, constructor: "stored"}),
      );

      const batch = pushed(updateWrite({data: {constructor: "refused"}}));

      Overlay.promote(batch, {}, {dropped: {0: {constructor: "refused"}}});

      assert.equal(LocalDatabase.baseRow(TODO, "t1").constructor, "stored");
    });

    it("lands a write on a column named like an inherited property", () => {
      LocalDatabase.putRow(TODO, base({constructor: "stored"}));

      const batch = pushed(updateWrite({data: {constructor: "written"}}));

      Overlay.promote(batch, {});

      assert.equal(LocalDatabase.baseRow(TODO, "t1").constructor, "written");
    });

    it("takes a value sent back for a column named like an inherited property", () => {
      LocalDatabase.putRow(TODO, base({constructor: "stored"}));

      const batch = pushed(updateWrite({data: {constructor: "lost"}}));

      Overlay.promote(
        batch,
        {
          0: {
            constructor: "winner",
            $revisions: {constructor: Number.MAX_SAFE_INTEGER},
          },
        },
        {dropped: {0: {constructor: "lost"}}},
      );

      assert.equal(LocalDatabase.baseRow(TODO, "t1").constructor, "winner");
    });

    it("takes the value the server sent back for a dropped column", () => {
      LocalDatabase.putRow(TODO, base({title: "stored"}));

      const batch = pushed(updateWrite({data: {title: "lost"}}));

      Overlay.promote(
        batch,
        {0: {title: "winner", $revisions: {title: Number.MAX_SAFE_INTEGER}}},
        {dropped: {0: {title: "lost"}}},
      );

      assert.equal(LocalDatabase.baseRow(TODO, "t1").title, "winner");
    });

    describe("of an edge an inverse of a to-many reads", () => {
      const LABEL = "MyApp.Label";

      beforeEach(() => {
        globalThis.Hologram.sync.model[TODO].relationships.labels = {
          optional: false,
          toMany: true,
          type: LABEL,
        };

        globalThis.Hologram.sync.model[LABEL] = {
          attributes: {id: "uuid", name: "string"},
          constraints: {},
          defaults: {},
          enumValues: {},
          frameworkAttributes: [],
          inverses: {
            todos: {
              forward: "labels",
              reference: false,
              sort: [],
              toMany: true,
              type: TODO,
            },
          },
          relationships: {},
          serverOnly: [],
        };

        Model.reset();
      });

      const labelEdge = (op) => ({
        id: "t1",
        op,
        relationship: "labels",
        target_id: "l1",
        type: TODO,
      });

      // The answer can land before the frame carrying the same edge on the label, and the label's
      // set would lose the row in between if only the to-many's own facts moved.
      it("promotes a confirmed edge into the ids filed for the inverse", () => {
        LocalDatabase.replaceFacts(LABEL, "todos", "l1", ["t2"]);

        Overlay.promote(pushed(labelEdge("add_relationship")), {});

        assert.deepStrictEqual(
          LocalDatabase.baseTargetIds(LABEL, "todos", "l1"),
          new Set(["t2", "t1"]),
        );

        // The frame carrying the same edge lands afterwards and changes nothing.
        LocalDatabase.addFact(LABEL, "todos", "l1", "t1");

        assert.deepStrictEqual(
          LocalDatabase.baseTargetIds(LABEL, "todos", "l1"),
          new Set(["t2", "t1"]),
        );
      });

      it("promotes a confirmed deleted edge out of the ids filed for the inverse", () => {
        LocalDatabase.replaceFacts(LABEL, "todos", "l1", ["t1", "t2"]);

        Overlay.promote(pushed(labelEdge("delete_relationship")), {});

        assert.deepStrictEqual(
          LocalDatabase.baseTargetIds(LABEL, "todos", "l1"),
          new Set(["t2"]),
        );

        LocalDatabase.deleteFact(LABEL, "todos", "l1", "t1");

        assert.deepStrictEqual(
          LocalDatabase.baseTargetIds(LABEL, "todos", "l1"),
          new Set(["t2"]),
        );
      });

      it("files nothing for an inverse whose ids were never filed", () => {
        Overlay.promote(pushed(labelEdge("add_relationship")), {});

        assert.isFalse(LocalDatabase.hasFacts(LABEL, "todos", "l1"));
      });
    });

    it("promotes a write no frame has carried", () => {
      LocalDatabase.putRow(TODO, base({votes: 5}));

      const batch = pushed(updateWrite({deltas: {votes: 2}}));

      Overlay.promote(batch, {});

      assert.equal(LocalDatabase.baseRow(TODO, "t1").votes, 7);
    });

    // The answer to a create the server did not perform - a role grant already held - carries
    // the stored row whole. Nothing is in the base under the id, and the write's own values are
    // this client's guess: the answer's row is what lands, not the guess.
    it("lands a create's kept row when the base holds none", () => {
      const batch = pushed(createWrite());

      Overlay.promote(batch, {
        0: {
          created_at: "2026-02-02T00:00:00.000000Z",
          done: true,
          id: "t1",
          project_id: "p9",
          title: "Theirs",
          updated_at: "2026-02-02T00:00:00.000000Z",
          votes: 9,
          $revisions: {done: 4, project_id: 4, title: 4, votes: 4},
        },
      });

      const row = LocalDatabase.baseRow(TODO, "t1");

      assert.equal(row.title, "Theirs");
      assert.equal(row.title$sort, "theirs");
      assert.equal(row.votes, 9);
      assert.equal(row.created_at, "2026-02-02T00:00:00.000000Z");
      assert.deepStrictEqual(row.$revisions, {
        done: 4,
        project_id: 4,
        title: 4,
        votes: 4,
      });
    });

    // The frame-first order: the row is already in the base, and the answer's whole row goes
    // through the same per-column absorb any kept does.
    it("still absorbs a create's kept columns into a base row that exists", () => {
      LocalDatabase.putRow(TODO, base({title: "Frame"}));

      const batch = pushed(createWrite());

      Overlay.promote(batch, {
        0: Object.assign(base({title: "Theirs"}), {
          $revisions: {done: 10, project_id: 10, title: 11, votes: 10},
        }),
      });

      const row = LocalDatabase.baseRow(TODO, "t1");

      assert.equal(row.title, "Theirs");
      assert.equal(row.$revisions.title, 11);
    });

    // An update's kept names columns, never a row - with nothing in the base to put them on,
    // there is nothing to do, and no row appears.
    it("leaves an update's kept alone when the base holds no row", () => {
      const batch = pushed(updateWrite({data: {title: "Mine"}}));

      Overlay.promote(batch, {
        0: {title: "Theirs", $revisions: {title: stamp + 1}},
      });

      // The whole table, not the one id: a kept with no id that was wrongly filed lands under
      // the key "undefined", where a read of "t1" would never see it.
      assert.deepStrictEqual(Object.keys(LocalDatabase.baseTable(TODO)), []);
    });

    it("files the value a lost column kept, with its revision", () => {
      LocalDatabase.putRow(TODO, base());

      const batch = pushed(updateWrite({data: {title: "Mine"}}));

      Overlay.promote(batch, {
        0: {title: "Theirs", $revisions: {title: stamp + 1}},
      });

      const row = LocalDatabase.baseRow(TODO, "t1");

      assert.equal(row.title, "Theirs");
      assert.equal(row.$revisions.title, stamp + 1);
      assert.equal(row.title$sort, "theirs");
    });

    it("holds a kept big integer as a BigInt", () => {
      LocalDatabase.putRow(TODO, base());

      const batch = pushed(updateWrite({data: {votes: 1}}));

      Overlay.promote(batch, {
        0: {votes: "9007199254740993", $revisions: {votes: stamp + 1}},
      });

      assert.strictEqual(
        LocalDatabase.baseRow(TODO, "t1").votes,
        9007199254740993n,
      );
    });

    // A resend of a batch already applied is answered from the record, so an answer can be older
    // than what frames have delivered since - taking it whole would walk the row backwards.
    it("leaves a base that has moved past what the answer kept", () => {
      LocalDatabase.putRow(
        TODO,
        base({
          title: "Newer still",
          $revisions: {done: 10, project_id: 10, title: stamp + 5, votes: 10},
        }),
      );

      const batch = pushed(updateWrite({data: {title: "Mine"}}));

      Overlay.promote(batch, {
        0: {title: "Theirs", $revisions: {title: stamp + 1}},
      });

      assert.equal(LocalDatabase.baseRow(TODO, "t1").title, "Newer still");
    });

    // The client has been told to let the row go, and filing it again would put back a row the
    // server says is not this client's to have.
    it("passes over what was kept for a row the base no longer holds", () => {
      const batch = pushed(updateWrite({data: {title: "Mine"}}));

      Overlay.promote(batch, {
        0: {title: "Theirs", $revisions: {title: stamp + 1}},
      });

      assert.isNull(LocalDatabase.baseRow(TODO, "t1"));
    });

    // The row the answer describes is what puts back the copy the fold took away - and absorbing
    // it first is what makes the delete's own fold answer correctly, since the row now carries a
    // revision above the delete's stamp.
    it("keeps a row whose delete lost, as the answer describes it", () => {
      LocalDatabase.putRow(TODO, base());

      const batch = pushed({id: "t1", op: "delete", stamp, type: TODO});

      Overlay.promote(batch, {
        0: {
          done: false,
          id: "t1",
          title: "Theirs",
          $revisions: {done: 10, project_id: 10, title: stamp + 1, votes: 10},
        },
      });

      assert.equal(LocalDatabase.baseRow(TODO, "t1").title, "Theirs");
    });

    it("lifts the clock past the revisions the answer names", () => {
      LocalDatabase.putRow(TODO, base());

      const batch = pushed(updateWrite({data: {title: "Mine"}}));

      Overlay.promote(batch, {
        0: {title: "Theirs", $revisions: {title: stamp + 1}},
      });

      assert.isAbove(Clock.stamp(), stamp + 1);
    });

    it("files what a write set when the answer names nothing kept", () => {
      LocalDatabase.putRow(TODO, base());

      const batch = pushed(updateWrite({data: {title: "Mine"}}));

      Overlay.promote(batch, {});

      assert.equal(LocalDatabase.baseRow(TODO, "t1").title, "Mine");
    });

    it("drops the batch's layer either way", () => {
      LocalDatabase.putRow(TODO, base());

      const batch = pushed(updateWrite({data: {title: "Mine"}}));
      batch.land(new Set([`${TODO} t1`]));

      Overlay.promote(batch, {});

      assert.isFalse(Overlay.names(TODO, "t1"));
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
