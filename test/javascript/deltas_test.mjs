"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import Deltas from "../../assets/js/deltas.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Model from "../../assets/js/model.mjs";

defineRuntimeGlobals();

describe("Deltas", () => {
  const PROJECT = "MyApp.Project";
  const TASK = "MyApp.Task";

  beforeEach(() => {
    globalThis.Hologram.sync = {
      model: {
        [PROJECT]: {
          attributes: {id: "uuid", name: "string"},
          relationships: {
            owner: {toMany: false, type: "MyApp.User"},
            tasks: {toMany: true, type: TASK},
          },
          serverOnly: [],
          sortKeys: [],
        },
        [TASK]: {
          attributes: {done: "boolean", id: "uuid", title: "string"},
          relationships: {},
          serverOnly: [],
          sortKeys: ["title"],
        },
      },
    };

    LocalDatabase.reset();
    Model.reset();
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

    // The pot is flat: what a row states about a relationship lives in the facts, so a row left
    // holding its own target ids would be answered from two places that can disagree.
    it("keeps the relationship out of the filed row", () => {
      Deltas.apply({
        put_entity: {[PROJECT]: [{id: "p1", name: "Website", tasks: ["t1"]}]},
      });

      assert.deepEqual(LocalDatabase.getRow(PROJECT, "p1"), {
        id: "p1",
        name: "Website",
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

    it("computes the sort key of an attribute the build orders by", () => {
      Deltas.apply({
        put_entity: {[TASK]: [{done: false, id: "t1", title: "Łódź"}]},
      });

      assert.equal(LocalDatabase.getRow(TASK, "t1").title_sort, "lodz");
    });

    it("computes no sort key for an attribute the build never orders by", () => {
      Deltas.apply({
        put_entity: {[PROJECT]: [{id: "p1", name: "Website"}]},
      });

      assert.isUndefined(LocalDatabase.getRow(PROJECT, "p1").name_sort);
    });

    it("computes a null sort key for an unset value", () => {
      Deltas.apply({
        put_entity: {[TASK]: [{done: false, id: "t1", title: null}]},
      });

      assert.isNull(LocalDatabase.getRow(TASK, "t1").title_sort);
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

      assert.equal(LocalDatabase.getRow(TASK, "t1").title_sort, "lodz");
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

      assert.equal(LocalDatabase.getRow(TASK, "t1").title_sort, "zurich");
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

    // A patch names a row the client was told about, so one it does not hold is one it has been
    // told to let go of - filing the changes alone would leave a row with holes.
    it("passes over a row the client does not hold", () => {
      Deltas.apply({patch_entity: {[TASK]: [{id: "t9", title: "Ship it"}]}});

      assert.isNull(LocalDatabase.getRow(TASK, "t9"));
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
