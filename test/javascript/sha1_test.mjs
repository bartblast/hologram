"use strict";

import {assert} from "./support/helpers.mjs";

import Sha1 from "../../assets/js/sha1.mjs";

function hex(bytes) {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

function digestOf(text) {
  return hex(Sha1.digest(new TextEncoder().encode(text)));
}

// The RFC 3174 vectors. The 56-byte one is the case that catches a padding mistake: its
// length leaves no room for the eight length bytes in the first block, so the message
// spills into a second one that is padding alone.
describe("Sha1", () => {
  describe("digest()", () => {
    it("digests a short message", () => {
      assert.equal(digestOf("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d");
    });

    it("digests a 56-byte message, whose padding spills into a second block", () => {
      assert.equal(
        digestOf("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
        "84983e441c3bd26ebaae4aa1f95129e5e54670f1",
      );
    });

    it("digests the empty message", () => {
      assert.equal(digestOf(""), "da39a3ee5e6b4b0d3255bfef95601890afd80709");
    });

    it("digests a message longer than one block", () => {
      assert.equal(
        digestOf("a".repeat(1000)),
        "291e9a6c66994949b57ba5e650361e98fc36b1ba",
      );
    });

    it("answers twenty bytes", () => {
      assert.equal(Sha1.digest(new Uint8Array([1, 2, 3])).length, 20);
    });
  });
});
