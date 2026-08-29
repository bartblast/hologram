"use strict";

import {assert} from "./support/helpers.mjs";

import Batches from "../../assets/js/batches.mjs";
import Overlay from "../../assets/js/overlay.mjs";

describe("Batches", () => {
  const TODO = "MyApp.Todo";

  const write = (id) => ({id, op: "delete", stamp: 1, type: TODO});

  beforeEach(() => {
    Batches.reset();
  });

  afterEach(() => {
    Batches.reset();
  });

  const wrote = (id) => {
    Batches.current().append(write(id));
  };

  describe("close()", () => {
    it("seals the open batch and queues it", () => {
      Batches.open("todos");
      wrote("t1");

      const batch = Batches.close();

      assert.equal(batch.seq, 1);
      assert.equal(batch.state, "pending");
      assert.deepStrictEqual(Batches.pending, [batch]);
    });

    it("takes the next sequence number per batch that ships", () => {
      Batches.open("todos");
      wrote("t1");
      Batches.close();

      Batches.open("todos");
      wrote("t2");

      assert.equal(Batches.close().seq, 2);
    });

    it("drops a batch that collected nothing, spending no sequence number", () => {
      Batches.open("todos");

      assert.isNull(Batches.close());
      assert.deepStrictEqual(Batches.pending, []);

      Batches.open("todos");
      wrote("t1");

      assert.equal(Batches.close().seq, 1);
    });

    it("leaves a sealed batch in the overlay, where its rows read as applied", () => {
      Batches.open("todos");
      wrote("t1");
      Batches.close();

      assert.equal(Overlay.durability(TODO, "t1"), "applied");
    });

    it("closes the batch opened last", () => {
      const outer = Batches.open("outer");
      const inner = Batches.open("inner");

      wrote("t1");

      assert.strictEqual(Batches.close(), inner);
      assert.strictEqual(Batches.current(), outer);
    });

    it("answers nothing when no batch is open", () => {
      assert.isNull(Batches.close());
    });
  });

  describe("current()", () => {
    it("answers nothing when no action has opened one", () => {
      assert.isNull(Batches.current());
    });

    it("answers the batch opened last", () => {
      Batches.open("outer");

      const inner = Batches.open("inner");

      assert.strictEqual(Batches.current(), inner);
    });
  });

  describe("discard()", () => {
    it("takes the batch's writes out of the overlay", () => {
      Batches.open("todos");
      wrote("t1");

      Batches.discard();

      assert.isFalse(Overlay.names(TODO, "t1"));
    });

    it("does not queue it, and spends no sequence number", () => {
      Batches.open("todos");
      wrote("t1");
      Batches.discard();

      assert.deepStrictEqual(Batches.pending, []);

      Batches.open("todos");
      wrote("t2");

      assert.equal(Batches.close().seq, 1);
    });

    it("discards the batch opened last", () => {
      const outer = Batches.open("outer");

      Batches.open("inner");
      Batches.discard();

      assert.strictEqual(Batches.current(), outer);
    });

    it("answers nothing when no batch is open", () => {
      assert.isNull(Batches.discard());
    });
  });

  describe("open()", () => {
    it("names the component the action ran on", () => {
      assert.equal(Batches.open("todos").target, "todos");
    });

    it("puts the batch in the overlay at once, so an action reads its own writes", () => {
      Batches.open("todos");
      wrote("t1");

      assert.isTrue(Overlay.names(TODO, "t1"));
    });
  });

  describe("reset()", () => {
    it("drops the open, the queued and the overlay's own", () => {
      Batches.open("todos");
      wrote("t1");
      Batches.close();
      Batches.open("todos");

      Batches.reset();

      assert.isNull(Batches.current());
      assert.deepStrictEqual(Batches.pending, []);
      assert.isFalse(Overlay.names(TODO, "t1"));
    });

    it("starts the sequence numbers over", () => {
      Batches.open("todos");
      wrote("t1");
      Batches.close();

      Batches.reset();

      Batches.open("todos");
      wrote("t2");

      assert.equal(Batches.close().seq, 1);
    });
  });
});
