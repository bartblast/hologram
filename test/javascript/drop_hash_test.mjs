"use strict";

import {assert} from "./support/helpers.mjs";

import DropHash from "../../assets/js/drop_hash.mjs";

// The same vectors Hologram.Sync.FrameTest checks drop_hash/2 against: the server hashes the ids
// a client is told to drop, and the client finds them only if both sides agree on every bit.
describe("DropHash", () => {
  describe("hash()", () => {
    it("hashes a salt and an id the way the server does", () => {
      assert.equal(
        DropHash.hash("salt", "02y1zRviSAYGVwSyzxs4q7"),
        "cb73f507346fd15a",
      );
    });

    it("hashes nothing at all as SHA-256 does", () => {
      assert.equal(DropHash.hash("", ""), "e3b0c44298fc1c14");
    });

    it("hashes a short message as SHA-256 does", () => {
      assert.equal(DropHash.hash("a", "b"), "fb8e20fc2e4c3f24");
    });

    it("hashes a message longer than one block", () => {
      assert.equal(
        DropHash.hash("x".repeat(40), "y".repeat(40)),
        "5f23e845240fffa4",
      );
    });

    it("hashes the same id differently under another salt", () => {
      const id = "02y1zRviSAYGVwSyzxs4q7";

      assert.notEqual(DropHash.hash("salt", id), DropHash.hash("other", id));
    });
  });
});
