"use strict";

import {assert} from "./support/helpers.mjs";

import Batch from "../../assets/js/batch.mjs";

describe("Batch", () => {
  const NOTE = "MyApp.Note";
  const TAG = "MyApp.Tag";

  const create = (id) => ({id, op: "create", type: NOTE});

  describe("append()", () => {
    it("keeps the writes in the order they were made", () => {
      const batch = new Batch("notes");

      batch.append(create("n1"));
      batch.append(create("n2"));

      assert.deepStrictEqual(
        batch.writes.map((write) => write.id),
        ["n1", "n2"],
      );
    });
  });

  describe("mark()", () => {
    it("moves the batch to the given state", () => {
      const batch = new Batch("notes");

      batch.mark("sending");

      assert.equal(batch.state, "sending");
    });
  });

  describe("rowKeys()", () => {
    it("names an edge's source row rather than its target", () => {
      const batch = new Batch("notes");

      batch.append({
        id: "t1",
        op: "add_relationship",
        relationship: "notes",
        target_id: "n1",
        type: TAG,
      });

      assert.deepStrictEqual(batch.rowKeys(), new Set([`${TAG} t1`]));
    });

    it("names the row of every write, whatever its op", () => {
      const batch = new Batch("notes");

      batch.append(create("n1"));
      batch.append({id: "n2", op: "update", type: NOTE});
      batch.append({id: "n3", op: "delete", type: NOTE});

      assert.deepStrictEqual(
        batch.rowKeys(),
        new Set([`${NOTE} n1`, `${NOTE} n2`, `${NOTE} n3`]),
      );
    });

    it("names a row once however many writes touch it", () => {
      const batch = new Batch("notes");

      batch.append(create("n1"));
      batch.append({id: "n1", op: "update", type: NOTE});

      assert.deepStrictEqual(batch.rowKeys(), new Set([`${NOTE} n1`]));
    });

    it("tells apart one id held by two types", () => {
      const batch = new Batch("notes");

      batch.append(create("x1"));
      batch.append({id: "x1", op: "update", type: TAG});

      assert.deepStrictEqual(
        batch.rowKeys(),
        new Set([`${NOTE} x1`, `${TAG} x1`]),
      );
    });
  });

  describe("seal()", () => {
    it("takes the sequence number and becomes pending", () => {
      const batch = new Batch("notes");

      assert.isNull(batch.seq);
      assert.equal(batch.state, "open");

      batch.seal(7);

      assert.equal(batch.seq, 7);
      assert.equal(batch.state, "pending");
    });
  });
});
