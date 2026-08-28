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

    it("overwrites a base row the confirming frame delivered first", () => {
      pushed(createWrite());

      const row = Overlay.foldRow(TODO, "t1", base({title: "From the frame"}));

      assert.equal(row.title, "Łódź");
      assert.equal(row.created_at, timestamp);
      assert.equal(row.$revisions.title, stamp);
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

    it("moves a counter by the delta and leaves its revision alone", () => {
      pushed(updateWrite({deltas: {votes: 2}}));

      const row = Overlay.foldRow(TODO, "t1", base());

      assert.equal(row.votes, 5);
      assert.equal(row.$revisions.votes, 10);
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

    it("answers nothing for a delete", () => {
      pushed({id: "t1", op: "delete", stamp, type: TODO});

      assert.isNull(Overlay.foldRow(TODO, "t1", base()));
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

    it("passes over a pending write naming another row of the same type", () => {
      pushed(updateWrite({data: {title: "Ship it"}, id: "t2"}));

      const row = base();

      assert.strictEqual(Overlay.foldRow(TODO, "t1", row), row);
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
