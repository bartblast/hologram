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

  describe("fromRecord()", () => {
    const record = {
      actorUserId: "u1",
      landed: [1],
      seq: 4,
      writes: [create("n1"), create("n2")],
    };

    it("builds a pending batch out of what was kept", async () => {
      const batch = Batch.fromRecord(record);

      assert.equal(batch.actorUserId, "u1");
      assert.equal(batch.seq, 4);
      assert.equal(batch.state, "pending");
      assert.deepStrictEqual(batch.writes, [create("n1"), create("n2")]);

      assert.isFalse(batch.isLanded(0));
      assert.isTrue(batch.isLanded(1));

      // Already written down, so the sender has nothing to wait for before shipping it.
      assert.isUndefined(await batch.recorded);
    });

    // The page that opened it is gone, and so is the component its cid named.
    it("names no target", () => {
      assert.isNull(Batch.fromRecord(record).target);
    });

    it("round-trips through record()", () => {
      assert.deepStrictEqual(Batch.fromRecord(record).record(), record);
    });
  });

  describe("isLanded() and land()", () => {
    it("marks the writes naming the given rows", () => {
      const batch = new Batch("notes");

      batch.append(create("n1"));
      batch.append(create("n2"));

      batch.land(new Set([`${NOTE} n1`]));

      assert.isTrue(batch.isLanded(0));
      assert.isFalse(batch.isLanded(1));
    });

    // Two writes to one row land together, because what came back is the row as the server left
    // it - both of them are in it.
    it("marks every write naming one row", () => {
      const batch = new Batch("notes");

      batch.append(create("n1"));
      batch.append({id: "n1", op: "update", type: NOTE});

      batch.land(new Set([`${NOTE} n1`]));

      assert.isTrue(batch.isLanded(0));
      assert.isTrue(batch.isLanded(1));
    });

    it("marks nothing for rows it does not name", () => {
      const batch = new Batch("notes");

      batch.append(create("n1"));

      batch.land(new Set([`${NOTE} n9`]));

      assert.isFalse(batch.isLanded(0));
    });

    // One id under two types is two rows, and a frame about one says nothing about the other.
    it("tells apart one id held by two types", () => {
      const batch = new Batch("notes");

      batch.append(create("x1"));
      batch.append({id: "x1", op: "update", type: TAG});

      batch.land(new Set([`${TAG} x1`]));

      assert.isFalse(batch.isLanded(0));
      assert.isTrue(batch.isLanded(1));
    });

    // A batch reaching two windows comes back as two frames, so what the first marked has to
    // survive the second.
    it("keeps what an earlier frame marked", () => {
      const batch = new Batch("notes");

      batch.append(create("n1"));
      batch.append(create("n2"));

      batch.land(new Set([`${NOTE} n1`]));
      batch.land(new Set([`${NOTE} n2`]));

      assert.isTrue(batch.isLanded(0));
      assert.isTrue(batch.isLanded(1));
    });

    it("marks nothing before a frame names anything", () => {
      const batch = new Batch("notes");

      batch.append(create("n1"));

      assert.isFalse(batch.isLanded(0));
    });

    it("answers whether it marked anything that was not marked already", () => {
      const batch = new Batch("notes");

      batch.append(create("n1"));

      assert.isTrue(batch.land(new Set([`${NOTE} n1`])));
      assert.isFalse(batch.land(new Set([`${NOTE} n1`])));
      assert.isFalse(batch.land(new Set([`${NOTE} n9`])));
    });
  });

  describe("mark()", () => {
    it("moves the batch to the given state", () => {
      const batch = new Batch("notes");

      batch.mark("sending");

      assert.equal(batch.state, "sending");
    });
  });

  describe("record()", () => {
    it("spells the kept fields and nothing else", () => {
      const batch = new Batch("notes");

      batch.append(create("n1"));
      batch.seal(4);

      assert.deepStrictEqual(Object.keys(batch.record()), [
        "actorUserId",
        "landed",
        "seq",
        "writes",
      ]);
    });

    it("lists the landed indices in order", () => {
      const batch = new Batch("notes");

      batch.append(create("n1"));
      batch.append(create("n2"));
      batch.append(create("n3"));
      batch.seal(4);

      batch.land(new Set([`${NOTE} n3`]));
      batch.land(new Set([`${NOTE} n1`]));

      assert.deepStrictEqual(batch.record().landed, [0, 2]);
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
