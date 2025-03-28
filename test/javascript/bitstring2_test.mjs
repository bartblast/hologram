"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Bitstring2 from "../../assets/js/bitstring2.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Bitstring2", () => {
  describe("concatSegments()", () => {
    it("single string binary segment", () => {
      const result = Bitstring2.concatSegments([
        Type.bitstringSegment(Type.string("Hologram"), {type: "binary"}),
      ]);

      const expected = {
        type: "bitstring",
        text: "Hologram",
        bytes: null,
        numLeftoverBits: 0,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("multiple string binary segments", () => {
      const result = Bitstring2.concatSegments([
        Type.bitstringSegment(Type.string("Holo"), {type: "binary"}),
        Type.bitstringSegment(Type.string("gram"), {type: "binary"}),
      ]);

      const expected = {
        type: "bitstring",
        text: "Hologram",
        bytes: null,
        numLeftoverBits: 0,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("single string utf8 segment", () => {
      const result = Bitstring2.concatSegments([
        Type.bitstringSegment(Type.string("Hologram"), {type: "utf8"}),
      ]);

      const expected = {
        type: "bitstring",
        text: "Hologram",
        bytes: null,
        numLeftoverBits: 0,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("multiple string utf8 segments", () => {
      const result = Bitstring2.concatSegments([
        Type.bitstringSegment(Type.string("Holo"), {type: "utf8"}),
        Type.bitstringSegment(Type.string("gram"), {type: "utf8"}),
      ]);

      const expected = {
        type: "bitstring",
        text: "Hologram",
        bytes: null,
        numLeftoverBits: 0,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("string binary and utf8 segments", () => {
      const result = Bitstring2.concatSegments([
        Type.bitstringSegment(Type.string("Holo"), {type: "binary"}),
        Type.bitstringSegment(Type.string("gram"), {type: "utf8"}),
      ]);

      const expected = {
        type: "bitstring",
        text: "Hologram",
        bytes: null,
        numLeftoverBits: 0,
      };

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("fromBits()", () => {
    it("empty", () => {
      const result = Bitstring2.fromBits([]);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array(0),
        numLeftoverBits: 0,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("single byte, byte-aligned", () => {
      const result = Bitstring2.fromBits([1, 0, 1, 0, 1, 0, 1, 0]);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([170]),
        numLeftoverBits: 0,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("single byte, not byte-aligned", () => {
      const result = Bitstring2.fromBits([1, 0, 1, 0]);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([160]),
        numLeftoverBits: 4,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("multiple bytes, byte-aligned", () => {
      // prettier-ignore
      const result = Bitstring2.fromBits([
        1, 0, 1, 0, 1, 0, 1, 0,
        0, 1, 0, 1, 0, 1, 0, 1
      ]);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([170, 85]),
        numLeftoverBits: 0,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("multiple bytes, not byte-aligned", () => {
      // prettier-ignore
      const result = Bitstring2.fromBits([
        1, 0, 1, 0, 1, 0, 1, 0,
        0, 1, 0, 1, 0, 1, 0, 1,
        1, 0, 1, 0
      ]);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([170, 85, 160]),
        numLeftoverBits: 4,
      };

      assert.deepStrictEqual(result, expected);
    });
  });

  it("fromText()", () => {
    const result = Bitstring2.fromText("Hologram");

    const expected = {
      type: "bitstring",
      text: "Hologram",
      bytes: null,
      numLeftoverBits: 0,
    };

    assert.deepStrictEqual(result, expected);
  });
});
