"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Bitstring from "../../assets/js/bitstring.mjs";
import HologramInterpreterError from "../../assets/js/errors/interpreter_error.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Bitstring", () => {
  describe("calculateBitCount()", () => {
    it("calculates bit count for bitstring with bytes and no leftover bits", () => {
      const bitstring = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([1, 2, 3]),
        leftoverBitCount: 0,
        hex: null,
      };

      assert.equal(Bitstring.calculateBitCount(bitstring), 24);
    });

    it("calculates bit count for bitstring with bytes and leftover bits", () => {
      const bitstring = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([1, 2, 224]),
        leftoverBitCount: 3,
        hex: null,
      };

      assert.equal(Bitstring.calculateBitCount(bitstring), 19);
    });

    it("calculates bit count for bitstring with ASCII text", () => {
      const bitstring = {
        type: "bitstring",
        text: "abc",
        bytes: null,
        leftoverBitCount: 0,
        hex: null,
      };

      assert.equal(Bitstring.calculateBitCount(bitstring), 24);
    });

    it("calculates bit count for bitstring with Unicode text", () => {
      const bitstring = {
        type: "bitstring",
        text: "全息图",
        bytes: null,
        leftoverBitCount: 0,
        hex: null,
      };

      assert.equal(Bitstring.calculateBitCount(bitstring), 72);
    });
  });

  describe("calculateSegmentBitCount()", () => {
    it("calculates bit count when size and unit are explicitly specified", () => {
      const segment = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
        size: Type.integer(16),
        unit: 2n,
      });

      assert.equal(Bitstring.calculateSegmentBitCount(segment), 32);
    });

    it("calculates bit count when size and unit are not specified", () => {
      const segment = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
      });

      assert.equal(Bitstring.calculateSegmentBitCount(segment), 8);
    });

    it("returns null when segment size can't be determined", () => {
      const value = Type.bitstring("hello");

      // This will cause resolveSegmentSize() to return null
      const segment = Type.bitstringSegment(value, {
        type: "bitstring",
      });

      assert.equal(Bitstring.calculateSegmentBitCount(segment), null);
    });
  });

  it("calculateTextByteCount()", () => {
    assert.equal(Bitstring.calculateTextByteCount("全息图"), 9);
  });

  describe("compare()", () => {
    describe("text-based comparison fast path", () => {
      it("returns 0 for identical text with no leftover bits", () => {
        const bitstring1 = Type.bitstring("hello");
        const bitstring2 = Type.bitstring("hello");
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, 0);
      });

      it("falls through to byte comparison for different text", () => {
        const bitstring1 = Type.bitstring("abc");
        const bitstring2 = Type.bitstring("abd");
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, -1);
      });

      it("falls through when one bitstring is not text-based", () => {
        const bitstring1 = Type.bitstring("abc");
        const bitstring2 = Bitstring.fromBytes([97, 98, 99]); // "abc" in bytes
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, 0);
      });

      it("handles Unicode text comparison", () => {
        const bitstring1 = Type.bitstring("全"); // Unicode character
        const bitstring2 = Type.bitstring("息"); // Different Unicode character
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, -1);
      });
    });

    describe("byte-aligned comparison (no leftover bits)", () => {
      it("returns 0 for equal byte arrays", () => {
        const bitstring1 = Bitstring.fromBytes([1, 2, 3]);
        const bitstring2 = Bitstring.fromBytes([1, 2, 3]);
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, 0);
      });

      it("returns -1 when first byte is smaller", () => {
        const bitstring1 = Bitstring.fromBytes([1, 2, 3]);
        const bitstring2 = Bitstring.fromBytes([2, 2, 3]);
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, -1);
      });

      it("returns 1 when first byte is larger", () => {
        const bitstring1 = Bitstring.fromBytes([2, 2, 3]);
        const bitstring2 = Bitstring.fromBytes([1, 2, 3]);
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, 1);
      });

      it("returns -1 when second byte is smaller", () => {
        const bitstring1 = Bitstring.fromBytes([1, 1, 3]);
        const bitstring2 = Bitstring.fromBytes([1, 2, 3]);
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, -1);
      });

      it("returns 1 when second byte is larger", () => {
        const bitstring1 = Bitstring.fromBytes([1, 3, 3]);
        const bitstring2 = Bitstring.fromBytes([1, 2, 3]);
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, 1);
      });

      it("returns -1 when first bitstring is shorter", () => {
        const bitstring1 = Bitstring.fromBytes([1, 2]);
        const bitstring2 = Bitstring.fromBytes([1, 2, 3]);
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, -1);
      });

      it("returns 1 when first bitstring is longer", () => {
        const bitstring1 = Bitstring.fromBytes([1, 2, 3]);
        const bitstring2 = Bitstring.fromBytes([1, 2]);
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, 1);
      });

      it("handles empty bitstrings", () => {
        const bitstring1 = Bitstring.fromBytes([]);
        const bitstring2 = Bitstring.fromBytes([]);
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, 0);
      });

      it("handles empty vs non-empty", () => {
        const bitstring1 = Bitstring.fromBytes([]);
        const bitstring2 = Bitstring.fromBytes([1]);
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, -1);
      });

      it("optimizes comparison with unrolled loop for longer arrays", () => {
        // Test with array longer than 4 bytes to trigger unrolled loop
        const bitstring1 = Bitstring.fromBytes([1, 2, 3, 4, 5, 6, 7, 8]);
        const bitstring2 = Bitstring.fromBytes([1, 2, 3, 4, 5, 6, 7, 9]);
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, -1);
      });

      it("compares byte arrays with unrolled loop optimization - first chunk differs", () => {
        const bitstring1 = Bitstring.fromBytes([1, 2, 3, 4, 5]);
        const bitstring2 = Bitstring.fromBytes([1, 2, 2, 4, 5]); // third byte differs
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, 1);
      });
    });

    describe("leftover bits comparison", () => {
      it("compares bitstrings where first has no leftover bits, second has leftover bits", () => {
        const bitstring1 = Bitstring.fromBytes([1, 2]); // 2 complete bytes, no leftover

        const bitstring2 = Type.bitstring([
          1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0,
        ]); // 2 complete bytes + 2 leftover bits

        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, -1);
      });

      it("compares bitstrings where first has leftover bits, second has no leftover bits", () => {
        const bitstring1 = Type.bitstring([
          1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0,
        ]); // 2 complete bytes + 2 leftover bits

        const bitstring2 = Bitstring.fromBytes([1, 2]); // 2 complete bytes, no leftover

        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, 1);
      });

      it("compares bitstrings with same number of complete bytes and different leftover bits", () => {
        const bitstring1 = Type.bitstring([1, 0, 0, 0, 0, 0, 0, 0, 1, 1]); // 1 complete byte + 2 leftover bits (11xx xxxx)
        const bitstring2 = Type.bitstring([1, 0, 0, 0, 0, 0, 0, 0, 1, 0]); // 1 complete byte + 2 leftover bits (10xx xxxx)
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, 1);
      });

      it("compares bitstrings with same leftover bit values but different counts", () => {
        const bitstring1 = Type.bitstring([1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1]); // 1 complete byte + 3 leftover bits
        const bitstring2 = Type.bitstring([1, 0, 0, 0, 0, 0, 0, 0, 1, 0]); // 1 complete byte + 2 leftover bits
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, 1);
      });

      it("returns 0 for bitstrings with identical leftover bits", () => {
        const bitstring1 = Type.bitstring([1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1]); // 1 complete byte + 3 leftover bits
        const bitstring2 = Type.bitstring([1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1]); // 1 complete byte + 3 leftover bits
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, 0);
      });
    });

    describe("different complete byte counts with leftover bits", () => {
      it("compares when first has more complete bytes and second has leftover bits", () => {
        const bitstring1 = Bitstring.fromBytes([1, 2, 3]); // 3 complete bytes

        const bitstring2 = Type.bitstring([
          1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0,
        ]); // 2 complete bytes + leftover

        const result = Bitstring.compare(bitstring1, bitstring2);

        // Should compare byte 3 (value 3) with leftover bits of second bitstring
        // Second bitstring's leftover bits: 10 (which is 128 when left-aligned)
        assert.equal(result, -1); // 3 < 128
      });

      it("compares when second has more complete bytes and first has leftover bits", () => {
        const bitstring1 = Type.bitstring([
          1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0,
        ]); // 2 complete bytes + leftover

        const bitstring2 = Bitstring.fromBytes([1, 2, 3]); // 3 complete bytes

        const result = Bitstring.compare(bitstring1, bitstring2);

        // Should compare leftover bits of first bitstring with byte 3 (value 3)
        // First bitstring's leftover bits: 10 (which is 128 when left-aligned)
        assert.equal(result, 1); // 128 > 3
      });

      it("handles case where longer bitstring byte equals shorter leftover bits", () => {
        // Create a bitstring where the next byte from longer equals the leftover masked bits from shorter
        const bitstring1 = Type.bitstring([
          1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0,
        ]); // bytes: [1, 192], leftover: 0

        const bitstring2 = Type.bitstring([1, 0, 0, 0, 0, 0, 0, 0, 1, 1]); // bytes: [1, 192], leftover: 2

        const result = Bitstring.compare(bitstring1, bitstring2);

        // First has more complete bytes, second has leftover
        // Next byte from first (192) should equal leftover masked bits from second (11xx xxxx = 192)
        // Since they're equal up to leftover bits, longer one wins
        assert.equal(result, 1);
      });

      it("compares when shorter has no leftover bits", () => {
        const bitstring1 = Bitstring.fromBytes([1, 2]); // 2 complete bytes, no leftover
        const bitstring2 = Bitstring.fromBytes([1, 2, 3]); // 3 complete bytes
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, -1);
      });
    });

    describe("edge cases", () => {
      it("handles single bit comparison", () => {
        const bitstring1 = Type.bitstring([1]); // single bit: 1
        const bitstring2 = Type.bitstring([0]); // single bit: 0
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, 1);
      });

      it("handles comparison with large byte values", () => {
        const bitstring1 = Bitstring.fromBytes([255, 254]);
        const bitstring2 = Bitstring.fromBytes([255, 255]);
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, -1);
      });

      it("handles text vs bytes comparison", () => {
        const bitstring1 = Type.bitstring("A"); // ASCII 65
        const bitstring2 = Bitstring.fromBytes([66]); // ASCII 66 ("B")
        const result = Bitstring.compare(bitstring1, bitstring2);

        assert.equal(result, -1);
      });
    });
  });

  describe("concat()", () => {
    it("handles empty array of bitstrings", () => {
      const result = Bitstring.concat([]);

      const expected = {
        type: "bitstring",
        text: "",
        bytes: null,
        leftoverBitCount: 0,
        hex: null,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("returns the single bitstring when the bitstrings array length is 1", () => {
      const bitstring = Bitstring.fromText("abc");
      const result = Bitstring.concat([bitstring]);

      assert.strictEqual(result, bitstring);
    });

    it("concatenates text-only bitstrings", () => {
      const bs1 = Bitstring.fromText("Hello");
      const bs2 = Bitstring.fromText(" ");
      const bs3 = Bitstring.fromText("World");

      const result = Bitstring.concat([bs1, bs2, bs3]);

      const expected = {
        type: "bitstring",
        text: "Hello World",
        bytes: null,
        leftoverBitCount: 0,
        hex: null,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("skips empty bitstrings with no bits", () => {
      const bs1 = Bitstring.fromBytes([1, 2]);
      const bs2 = Bitstring.fromBytes([]);
      const bs3 = Bitstring.fromBytes([3, 4]);

      const result = Bitstring.concat([bs1, bs2, bs3]);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([1, 2, 3, 4]),
        leftoverBitCount: 0,
        hex: null,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("concatenates byte-aligned bitstrings with no leftover bits", () => {
      const bs1 = Bitstring.fromBytes([1, 2, 3]);
      const bs2 = Bitstring.fromBytes([4, 5]);
      const bs3 = Bitstring.fromBytes([6]);

      const result = Bitstring.concat([bs1, bs2, bs3]);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([1, 2, 3, 4, 5, 6]),
        leftoverBitCount: 0,
        hex: null,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("converts text bitstring to bytes when concatenating with byte bitstring without leftover bits", () => {
      const bs1 = Bitstring.fromText("ab");
      const bs2 = Bitstring.fromBytes([99, 100]); // "cd" in ASCII

      const result = Bitstring.concat([bs1, bs2]);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([97, 98, 99, 100]), // "abcd" in ASCII
        leftoverBitCount: 0,
        hex: null,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("converts text bitstring to bytes when concatenating with byte bitstring with leftover bits", () => {
      const bs1 = Bitstring.fromText("ab");

      const bs2 = Bitstring.fromBytes([99, 255]);
      bs2.leftoverBitCount = 3;

      const result = Bitstring.concat([bs1, bs2]);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([97, 98, 99, 224]),
        leftoverBitCount: 3,
        hex: null,
      };

      assert.deepStrictEqual(result, expected);
    });

    describe("handles bitstrings with leftover bits", () => {
      it("when leftover bits are in the first single-byte bitstring", () => {
        // 10101 (5 bits)
        const bs1 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xa8]), // 10101000
          leftoverBitCount: 5,
          hex: null,
        };

        // 10111011 (full byte)
        const bs2 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xbb]), // 10111011
          leftoverBitCount: 0,
          hex: null,
        };

        // 11001100 (full byte)
        const bs3 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xcc]), // 11001100
          leftoverBitCount: 0,
          hex: null,
        };

        const result = Bitstring.concat([bs1, bs2, bs3]);

        // Expected: 10101101 11011110 01100000
        // Which is: [0xAD, 0xDE, 0x60] with 5 bits in the last byte
        const expected = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xad, 0xde, 0x60]),
          leftoverBitCount: 5,
          hex: null,
        };

        assert.deepStrictEqual(result, expected);
      });

      it("when leftover bits are in the first multi-byte bitstring", () => {
        // 10101010, 10111 (5 bits in the second byte)
        const bs1 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa, 0xb8]), // 10101010, 10111000
          leftoverBitCount: 5,
          hex: null,
        };

        // 11001100, 11011101 (full bytes)
        const bs2 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xcc, 0xdd]), // 11001100, 11011101
          leftoverBitCount: 0,
          hex: null,
        };

        // 11101110, 11111111 (full bytes)
        const bs3 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xee, 0xff]), // 11101110, 11111111
          leftoverBitCount: 0,
          hex: null,
        };

        const result = Bitstring.concat([bs1, bs2, bs3]);

        // Expected: 10101010, 10111110, 01100110, 11101111, 01110111, 11111000
        // Which is: [0xAA, 0xBE, 0x66, 0xEF, 0x77, 0xF8] with 5 bits in the last byte
        const expected = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa, 0xbe, 0x66, 0xef, 0x77, 0xf8]),
          leftoverBitCount: 5,
          hex: null,
        };

        assert.deepStrictEqual(result, expected);
      });

      it("when leftover bits are in the middle single-byte bitstring", () => {
        // 10101010 (full byte)
        const bs1 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa]), // 10101010
          leftoverBitCount: 0,
          hex: null,
        };

        // 10111 (5 bits)
        const bs2 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xb8]), // 10111000
          leftoverBitCount: 5,
          hex: null,
        };

        // 11001100 (full byte)
        const bs3 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xcc]), // 11001100
          leftoverBitCount: 0,
          hex: null,
        };

        const result = Bitstring.concat([bs1, bs2, bs3]);

        // Expected: 10101010 10111110 01100000
        // Which is: [0xAA, 0xBE, 0x60] with 5 bits in the last byte
        const expected = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa, 0xbe, 0x60]),
          leftoverBitCount: 5,
          hex: null,
        };

        assert.deepStrictEqual(result, expected);
      });

      it("when leftover bits are in the middle multi-byte bitstring", () => {
        // 10101010, 10111011 (full bytes)
        const bs1 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa, 0xbb]), // 10101010, 10111011
          leftoverBitCount: 0,
          hex: null,
        };

        // 11001100, 11011 (5 bits in the second byte)
        const bs2 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xcc, 0xd8]), // 11001100, 11011000
          leftoverBitCount: 5,
          hex: null,
        };

        // 11101110, 11111111 (full bytes)
        const bs3 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xee, 0xff]), // 11101110, 11111111
          leftoverBitCount: 0,
          hex: null,
        };

        const result = Bitstring.concat([bs1, bs2, bs3]);

        // Expected: 10101010, 10111011, 11001100, 11011111, 01110111, 11111000
        // Which is: [0xaa, 0xbb, 0xcc, 0xdf, 0x77, 0xf8] with 5 bits in the last byte
        const expected = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xdf, 0x77, 0xf8]),
          leftoverBitCount: 5,
          hex: null,
        };

        assert.deepStrictEqual(result, expected);
      });

      it("when leftover bits are in the last single-byte bitstring", () => {
        // 10101010 (full byte)
        const bs1 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa]), // 10101010
          leftoverBitCount: 0,
          hex: null,
        };

        // 10111011 (full byte)
        const bs2 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xbb]), // 10111011
          leftoverBitCount: 0,
          hex: null,
        };

        // 11001 (5 bits)
        const bs3 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xc8]), // 11001000
          leftoverBitCount: 5,
          hex: null,
        };

        const result = Bitstring.concat([bs1, bs2, bs3]);

        // Expected: 10101010, 10111011, 11001000
        // Which is: [0xAA, 0xBB, 0xC8] with 5 bits in the last byte
        const expected = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa, 0xbb, 0xc8]),
          leftoverBitCount: 5,
          hex: null,
        };

        assert.deepStrictEqual(result, expected);
      });

      it("when leftover bits are in the last multi-byte bitstring", () => {
        // 10101010, 10111011 (full bytes)
        const bs1 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa, 0xbb]), // 10101010, 10111011
          leftoverBitCount: 0,
          hex: null,
        };

        // 11001100, 11011101 (full bytes)
        const bs2 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xcc, 0xdd]), // 11001100, 11011101
          leftoverBitCount: 0,
          hex: null,
        };

        // 11101110, 11111 (5 bits in the second byte)
        const bs3 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xee, 0xf8]), // 11101110, 11111000
          leftoverBitCount: 5,
          hex: null,
        };

        const result = Bitstring.concat([bs1, bs2, bs3]);

        // Expected: 10101010, 10111011, 11001100, 11011101, 11101110, 11111000
        // Which is: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xF8] with 5 bits in the last byte
        const expected = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xf8]),
          leftoverBitCount: 5,
          hex: null,
        };

        assert.deepStrictEqual(result, expected);
      });

      it("when all single-byte bitstrings have leftover bits", () => {
        // 10101 (5 bits)
        const bs1 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xa8]), // 10101000
          leftoverBitCount: 5,
          hex: null,
        };

        // 1101 (4 bits)
        const bs2 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xd0]), // 11010000
          leftoverBitCount: 4,
          hex: null,
        };

        // 111 (3 bits)
        const bs3 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xe0]), // 11100000
          leftoverBitCount: 3,
          hex: null,
        };

        const result = Bitstring.concat([bs1, bs2, bs3]);

        // Expected: 10101110, 11110000
        // Which is: [0xAE, 0xF0] with 4 bits in the last byte
        const expected = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xae, 0xf0]),
          leftoverBitCount: 4,
          hex: null,
        };

        assert.deepStrictEqual(result, expected);
      });

      it("when all multi-byte bitstrings have leftover bits", () => {
        // 10101010, 10101 (5 bits in the second byte)
        const bs1 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa, 0xa8]), // 10101010, 10101000
          leftoverBitCount: 5,
          hex: null,
        };

        // 10111011, 1101 (4 bits in the second byte)
        const bs2 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xbb, 0xd0]), // 10111011, 11010000
          leftoverBitCount: 4,
          hex: null,
        };

        // 11001100, 111 (3 bits in the second byte)
        const bs3 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xcc, 0xe0]), // 11001100, 11100000
          leftoverBitCount: 3,
          hex: null,
        };

        const result = Bitstring.concat([bs1, bs2, bs3]);

        // Expected: 10101010, 10101101, 11011110, 11100110 01110000
        // Which is: [0xAA, 0xAD, 0xDE, 0xE6, 0x70] with 4 bits in the last byte
        const expected = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa, 0xad, 0xde, 0xe6, 0x70]),
          leftoverBitCount: 4,
          hex: null,
        };

        assert.deepStrictEqual(result, expected);
      });

      it("when leftover bits are in the first and the one before last single-byte bitstring", () => {
        // 10101 (5 bits)
        const bs1 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xa8]), // 10101000
          leftoverBitCount: 5,
          hex: null,
        };

        // 10111011 (full byte)
        const bs2 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xbb]), // 10111011
          leftoverBitCount: 0,
          hex: null,
        };

        // 11001 (5 bits)
        const bs3 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xc8]), // 11001000
          leftoverBitCount: 5,
          hex: null,
        };

        // 11011101 (full byte)
        const bs4 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xdd]), // 11011101
          leftoverBitCount: 0,
          hex: null,
        };

        const result = Bitstring.concat([bs1, bs2, bs3, bs4]);

        // Expected: 10101101, 11011110, 01110111, 01000000
        // Which is: [0xAD, 0xDE, 0x77, 0x40] with 2 bits in the last byte
        const expected = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xad, 0xde, 0x77, 0x40]),
          leftoverBitCount: 2,
          hex: null,
        };

        assert.deepStrictEqual(result, expected);
      });

      it("when leftover bits are in the first and the one before last multi-byte bitstring", () => {
        // 10101010, 10111 (5 bits in the second byte)
        const bs1 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa, 0xb8]), // 10101010, 10111000
          leftoverBitCount: 5,
          hex: null,
        };

        // 11001100, 11011101 (full bytes)
        const bs2 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xcc, 0xdd]), // 11001100, 11011101
          leftoverBitCount: 0,
          hex: null,
        };

        // 11101110, 11111 (5 bits in the second byte)
        const bs3 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xee, 0xf8]), // 11101110, 11111000
          leftoverBitCount: 5,
          hex: null,
        };

        // 10001000, 10011001 (full bytes)
        const bs4 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0x88, 0x99]), // 10001000, 10011001
          leftoverBitCount: 0,
          hex: null,
        };

        const result = Bitstring.concat([bs1, bs2, bs3, bs4]);

        // Expected: 10101010, 10111110, 01100110, 11101111, 01110111, 11100010, 00100110, 01000000
        // Which is: [0xAA, 0xBE, 0x66, 0xEF, 0x77, 0xE2, 0x26, 0x40] with 2 bits in the last byte
        const expected = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([
            0xaa, 0xbe, 0x66, 0xef, 0x77, 0xe2, 0x26, 0x40,
          ]),
          leftoverBitCount: 2,
          hex: null,
        };

        assert.deepStrictEqual(result, expected);
      });

      it("when leftover bits are in the second and last single-byte bitstring", () => {
        // 10101010 (full byte)
        const bs1 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa]), // 10101010
          leftoverBitCount: 0,
          hex: null,
        };

        // 10111 (5 bits)
        const bs2 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xb8]), // 10111000
          leftoverBitCount: 5,
          hex: null,
        };

        // 11001100 (full byte)
        const bs3 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xcc]), // 11001100
          leftoverBitCount: 0,
          hex: null,
        };

        // 11011 (5 bits)
        const bs4 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xd8]), // 11011000
          leftoverBitCount: 5,
          hex: null,
        };

        const result = Bitstring.concat([bs1, bs2, bs3, bs4]);

        // Expected: 10101010, 10111110, 01100110, 11000000
        // Which is: [0xAA, 0xBE, 0x66, 0xC0] with 2 bits in the last byte
        const expected = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa, 0xbe, 0x66, 0xc0]),
          leftoverBitCount: 2,
          hex: null,
        };

        assert.deepStrictEqual(result, expected);
      });

      it("when leftover bits are in the second and last multi-byte bitstring", () => {
        // 10101010, 10111011 (full bytes)
        const bs1 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa, 0xbb]), // 10101010, 10111011
          leftoverBitCount: 0,
          hex: null,
        };

        // 11001100, 11011 (5 bits in the second byte)
        const bs2 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xcc, 0xd8]), // 11001100, 11011000
          leftoverBitCount: 5,
          hex: null,
        };

        // 11101110, 11111111 (full bytes)
        const bs3 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xee, 0xff]), // 11101110, 11111111
          leftoverBitCount: 0,
          hex: null,
        };

        // 10001000, 10011 (5 bits in the second byte)
        const bs4 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0x88, 0x98]), // 10001000, 10011000
          leftoverBitCount: 5,
          hex: null,
        };

        const result = Bitstring.concat([bs1, bs2, bs3, bs4]);

        // Expected: 10101010, 10111011 11001100, 11011111, 01110111, 11111100, 01000100, 11000000
        // Which is: [0xAA, 0xBB, 0xCC, 0xDF, 0x77, 0xFC, 0x44, 0xC0] with 2 bits in the last byte
        const expected = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([
            0xaa, 0xbb, 0xcc, 0xdf, 0x77, 0xfc, 0x44, 0xc0,
          ]),
          leftoverBitCount: 2,
          hex: null,
        };

        assert.deepStrictEqual(result, expected);
      });

      it("when the number of result bytes is smaller than the number of bitstrings", () => {
        // 1 (1 bit)
        const bs1 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0x80]), // 10000000
          leftoverBitCount: 1,
          hex: null,
        };

        // 101 (3 bits)
        const bs2 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xa0]), // 10100000
          leftoverBitCount: 3,
          hex: null,
        };

        // 10101 (5 bits)
        const bs3 = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xa8]), // 10101000
          leftoverBitCount: 5,
          hex: null,
        };

        const result = Bitstring.concat([bs1, bs2, bs3]);

        // Expected: 11011010, 10000000
        // Which is: [0xDA, 0x80] with 1 bit in the last byte
        const expected = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xda, 0x80]),
          leftoverBitCount: 1,
          hex: null,
        };

        assert.deepStrictEqual(result, expected);
      });
    });
  });

  describe("decodeSegmentChunk()", () => {
    describe("binary segment type", () => {
      it("returns the chunk unchanged", () => {
        const chunk = Type.bitstring("abc");

        const segment = Type.bitstringSegment(Type.variablePattern("value"), {
          type: "binary",
        });

        const result = Bitstring.decodeSegmentChunk(segment, chunk);

        assert.strictEqual(result, chunk);
      });
    });

    describe("bitstring segment type", () => {
      it("returns the chunk unchanged", () => {
        const chunk = Type.bitstring("abc");

        const segment = Type.bitstringSegment(Type.variablePattern("value"), {
          type: "bitstring",
        });

        const result = Bitstring.decodeSegmentChunk(segment, chunk);

        assert.strictEqual(result, chunk);
      });
    });

    describe("float segment type", () => {
      it("decodes a float with default big-endian modifier", () => {
        const chunk = Bitstring.fromBytes([64, 94, 221, 47, 26, 159, 190, 119]);

        const segment = Type.bitstringSegment(Type.variablePattern("value"), {
          type: "float",
        });

        const result = Bitstring.decodeSegmentChunk(segment, chunk);

        assert.deepStrictEqual(result, Type.float(123.456));
      });

      it("decodes a float with explicit big-endian modifier", () => {
        const chunk = Bitstring.fromBytes([64, 94, 221, 47, 26, 159, 190, 119]);

        const segment = Type.bitstringSegment(Type.variablePattern("value"), {
          type: "float",
          endianness: "big",
        });

        const result = Bitstring.decodeSegmentChunk(segment, chunk);

        assert.deepStrictEqual(result, Type.float(123.456));
      });

      it("decodes a float with little-endian modifier", () => {
        const chunk = Bitstring.fromBytes([119, 190, 159, 26, 47, 221, 94, 64]);

        const segment = Type.bitstringSegment(Type.variablePattern("value"), {
          type: "float",
          endianness: "little",
        });

        const result = Bitstring.decodeSegmentChunk(segment, chunk);

        assert.deepStrictEqual(result, Type.float(123.456));
      });
    });

    describe("integer segment type", () => {
      it("decodes an integer with default (signedness and endianness) modifiers", () => {
        const chunk = Bitstring.fromBytes([0xaa, 0xbb]);

        const segment = Type.bitstringSegment(Type.variablePattern("value"), {
          type: "integer",
          size: Type.integer(16n),
        });

        const result = Bitstring.decodeSegmentChunk(segment, chunk);

        assert.deepStrictEqual(result, Type.integer(43707n));
      });

      it("decodes an integer with unsigned and big-endian modifiers", () => {
        const chunk = Bitstring.fromBytes([0xaa, 0xbb]);

        const segment = Type.bitstringSegment(Type.variablePattern("value"), {
          type: "integer",
          size: Type.integer(16n),
          signedness: "unsigned",
          endianness: "big",
        });

        const result = Bitstring.decodeSegmentChunk(segment, chunk);

        assert.deepStrictEqual(result, Type.integer(43707n));
      });

      it("decodes an integer with unsigned and little-endian modifiers", () => {
        const chunk = Bitstring.fromBytes([0xaa, 0xbb]);

        const segment = Type.bitstringSegment(Type.variablePattern("value"), {
          type: "integer",
          size: Type.integer(16n),
          signedness: "unsigned",
          endianness: "little",
        });

        const result = Bitstring.decodeSegmentChunk(segment, chunk);

        assert.deepStrictEqual(result, Type.integer(48042n));
      });

      it("decodes an integer with signed and big-endian modifiers", () => {
        const chunk = Bitstring.fromBytes([0xaa, 0xbb]);

        const segment = Type.bitstringSegment(Type.variablePattern("value"), {
          type: "integer",
          size: Type.integer(16n),
          signedness: "signed",
          endianness: "big",
        });

        const result = Bitstring.decodeSegmentChunk(segment, chunk);

        assert.deepStrictEqual(result, Type.integer(-21829n));
      });

      it("decodes an integer with signed and little-endian modifiers", () => {
        const chunk = Bitstring.fromBytes([0xaa, 0xbb]);

        const segment = Type.bitstringSegment(Type.variablePattern("value"), {
          type: "integer",
          size: Type.integer(16n),
          signedness: "signed",
          endianness: "little",
        });

        const result = Bitstring.decodeSegmentChunk(segment, chunk);

        assert.deepStrictEqual(result, Type.integer(-17494n));
      });
    });

    it("raises error if the used type modifier is not yet implemented in Hologram", () => {
      const chunk = Bitstring.fromBytes([0, 97]);

      const segment = Type.bitstringSegment(Type.variablePattern("value"), {
        type: "utf16",
      });

      const expectedMessage =
        "utf16 segment type modifier is not yet implemented in Hologram";

      assert.throw(
        () => Bitstring.decodeSegmentChunk(segment, chunk),
        HologramInterpreterError,
        expectedMessage,
      );
    });
  });

  describe("decodeUtf8CodePoint()", () => {
    it("decodes 1-byte UTF-8 sequence (ASCII)", () => {
      // 'A' = 0x41 = U+0041
      const bytes = new Uint8Array([0x41]);
      const codePoint = Bitstring.decodeUtf8CodePoint(bytes, 0, 1);
      assert.equal(codePoint, 0x41);
    });

    it("decodes 2-byte UTF-8 sequence", () => {
      // '£' = 0xC2 0xA3 = U+00A3 (pound sign)
      const bytes = new Uint8Array([0xc2, 0xa3]);
      const codePoint = Bitstring.decodeUtf8CodePoint(bytes, 0, 2);
      assert.equal(codePoint, 0xa3);
    });

    it("decodes 3-byte UTF-8 sequence", () => {
      // '€' = 0xE2 0x82 0xAC = U+20AC (euro sign)
      const bytes = new Uint8Array([0xe2, 0x82, 0xac]);
      const codePoint = Bitstring.decodeUtf8CodePoint(bytes, 0, 3);
      assert.equal(codePoint, 0x20ac);
    });

    it("decodes 4-byte UTF-8 sequence", () => {
      // '𐍈' = 0xF0 0x90 0x8D 0x88 = U+10348 (Gothic letter hwair)
      const bytes = new Uint8Array([0xf0, 0x90, 0x8d, 0x88]);
      const codePoint = Bitstring.decodeUtf8CodePoint(bytes, 0, 4);
      assert.equal(codePoint, 0x10348);
    });

    it("decodes from non-zero start position", () => {
      // Test decoding '£' starting at position 2
      const bytes = new Uint8Array([0x41, 0x42, 0xc2, 0xa3]);
      const codePoint = Bitstring.decodeUtf8CodePoint(bytes, 2, 2);
      assert.equal(codePoint, 0xa3);
    });
  });

  describe("fromBits()", () => {
    it("empty", () => {
      const result = Bitstring.fromBits([]);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array(0),
        leftoverBitCount: 0,
        hex: null,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("single byte, byte-aligned", () => {
      const result = Bitstring.fromBits([1, 0, 1, 0, 1, 0, 1, 0]);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([170]),
        leftoverBitCount: 0,
        hex: null,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("single byte, not byte-aligned", () => {
      const result = Bitstring.fromBits([1, 0, 1, 0]);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([160]),
        leftoverBitCount: 4,
        hex: null,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("multiple bytes, byte-aligned", () => {
      // prettier-ignore
      const result = Bitstring.fromBits([
        1, 0, 1, 0, 1, 0, 1, 0,
        0, 1, 0, 1, 0, 1, 0, 1
      ]);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([170, 85]),
        leftoverBitCount: 0,
        hex: null,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("multiple bytes, not byte-aligned", () => {
      // prettier-ignore
      const result = Bitstring.fromBits([
        1, 0, 1, 0, 1, 0, 1, 0,
        0, 1, 0, 1, 0, 1, 0, 1,
        1, 0, 1, 0
      ]);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([170, 85, 160]),
        leftoverBitCount: 4,
        hex: null,
      };

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("fromBytes()", () => {
    it("creates bitstring from Uint8Array", () => {
      const bytes = new Uint8Array([1, 2, 3]);
      const result = Bitstring.fromBytes(bytes);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: bytes,
        leftoverBitCount: 0,
        hex: null,
      };

      assert.deepStrictEqual(result, expected);
      assert.strictEqual(result.bytes, bytes);
    });

    it("creates bitstring from regular array", () => {
      const bytes = [1, 2, 3];
      const result = Bitstring.fromBytes(bytes);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([1, 2, 3]),
        leftoverBitCount: 0,
        hex: null,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("handles empty array", () => {
      const result = Bitstring.fromBytes([]);

      const expected = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([]),
        leftoverBitCount: 0,
        hex: null,
      };

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("fromSegments()", () => {
    it("returns an empty bitstring for an empty array of segments", () => {
      assert.deepStrictEqual(Bitstring.fromSegments([]), Type.bitstring(""));
    });

    it("creates a bitstring from a single bitstring-valued segment", () => {
      const value = Type.bitstring("Hologram");

      const segments = [Type.bitstringSegment(value, {type: "bitstring"})];
      const result = Bitstring.fromSegments(segments);

      assert.equal(result, value);
    });

    it("creates a bitstring from a single float-valued segment", () => {
      const segments = [
        Type.bitstringSegment(Type.float(1.23), {type: "float"}),
      ];

      const result = Bitstring.fromSegments(segments);

      const expected = Bitstring.fromBytes([
        63, 243, 174, 20, 122, 225, 71, 174,
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("creates a bitstring from a single integer-valued segment", () => {
      const segments = [
        Type.bitstringSegment(Type.integer(3425778934n), {
          type: "integer",
          size: Type.integer(32),
        }),
      ];

      const result = Bitstring.fromSegments(segments);
      const expected = Bitstring.fromBytes([204, 49, 60, 246]);

      assert.deepStrictEqual(result, expected);
    });

    it("creates a bitstring from a single string-valued segment", () => {
      const segments = [
        Type.bitstringSegment(Type.string("Hologram"), {type: "binary"}),
      ];

      const result = Bitstring.fromSegments(segments);

      assert.deepStrictEqual(result, Type.bitstring("Hologram"));
    });

    it("creates a bitstring from multiple segments that have different value types", () => {
      const segments = [
        Type.bitstringSegment(Type.integer(123), {type: "integer"}),
        Type.bitstringSegment(Type.string("Hologram"), {type: "binary"}),
        Type.bitstringSegment(Type.float(1.23), {type: "float"}),
      ];

      const result = Bitstring.fromSegments(segments);

      const expected = Bitstring.fromBytes([
        123, 72, 111, 108, 111, 103, 114, 97, 109, 63, 243, 174, 20, 122, 225,
        71, 174,
      ]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("fromSegmentWithBitstringValue()", () => {
    it("when size is not specified", () => {
      const value = Type.bitstring("Hologram");
      const segment = Type.bitstringSegment(value, {type: "bitstring"});
      const result = Bitstring.fromSegmentWithBitstringValue(segment);

      assert.equal(result, value);
    });

    it("when size is specified", () => {
      const value = Bitstring.fromBytes([0xaa, 0xbb, 0xcc]); // 10101010, 10111011, 11001100

      const segment = Type.bitstringSegment(value, {
        type: "bitstring",
        size: Type.integer(12),
      });

      const result = Bitstring.fromSegmentWithBitstringValue(segment);

      const expected = Bitstring.fromBytes([0xaa, 0xb0]); // 10101010, 10110000
      expected.leftoverBitCount = 4;

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("fromSegmentWithFloatValue()", () => {
    describe("64-bit", () => {
      describe("float value", () => {
        describe("positive", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.float(123.45), {
              type: "float",
              size: Type.integer(32),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([64, 94, 220, 204, 204, 204, 204, 205]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.float(123.45), {
              type: "float",
              size: Type.integer(32),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([205, 204, 204, 204, 204, 220, 94, 64]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("negative", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.float(-123.45), {
              type: "float",
              size: Type.integer(32),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([192, 94, 220, 204, 204, 204, 204, 205]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.float(-123.45), {
              type: "float",
              size: Type.integer(32),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([205, 204, 204, 204, 204, 220, 94, 192]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("+0", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.float(0.0), {
              type: "float",
              size: Type.integer(32),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0, 0, 0, 0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.float(0.0), {
              type: "float",
              size: Type.integer(32),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0, 0, 0, 0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("-0", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.float(-0.0), {
              type: "float",
              size: Type.integer(32),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([128, 0, 0, 0, 0, 0, 0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.float(-0.0), {
              type: "float",
              size: Type.integer(32),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0, 0, 0, 0, 128]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });
      });

      describe("integer value", () => {
        describe("positive", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(123), {
              type: "float",
              size: Type.integer(32),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([64, 94, 192, 0, 0, 0, 0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(123), {
              type: "float",
              size: Type.integer(32),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0, 0, 192, 94, 64]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("negative", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(-123), {
              type: "float",
              size: Type.integer(32),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([192, 94, 192, 0, 0, 0, 0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(-123), {
              type: "float",
              size: Type.integer(32),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0, 0, 192, 94, 192]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("0", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(0), {
              type: "float",
              size: Type.integer(32),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0, 0, 0, 0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(0), {
              type: "float",
              size: Type.integer(32),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0, 0, 0, 0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });
      });
    });

    describe("32-bit", () => {
      describe("float value", () => {
        describe("positive", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.float(123.45), {
              type: "float",
              size: Type.integer(16),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([66, 246, 230, 102]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.float(123.45), {
              type: "float",
              size: Type.integer(16),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([102, 230, 246, 66]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("negative", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.float(-123.45), {
              type: "float",
              size: Type.integer(16),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([194, 246, 230, 102]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.float(-123.45), {
              type: "float",
              size: Type.integer(16),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([102, 230, 246, 194]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("+0", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.float(0.0), {
              type: "float",
              size: Type.integer(16),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.float(0.0), {
              type: "float",
              size: Type.integer(16),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("-0", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.float(-0.0), {
              type: "float",
              size: Type.integer(16),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([128, 0, 0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.float(-0.0), {
              type: "float",
              size: Type.integer(16),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 128]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });
      });

      describe("integer value", () => {
        describe("positive", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(123), {
              type: "float",
              size: Type.integer(16),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([66, 246, 0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(123), {
              type: "float",
              size: Type.integer(16),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0, 246, 66]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("negative", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(-123), {
              type: "float",
              size: Type.integer(16),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([194, 246, 0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(-123), {
              type: "float",
              size: Type.integer(16),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0, 246, 194]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("0", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(0), {
              type: "float",
              size: Type.integer(16),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(0), {
              type: "float",
              size: Type.integer(16),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });
      });
    });

    describe("16-bit", () => {
      describe("float value", () => {
        describe("positive", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.float(123.45), {
              type: "float",
              size: Type.integer(8),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([87, 183]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.float(123.45), {
              type: "float",
              size: Type.integer(8),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([183, 87]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("negative", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.float(-123.45), {
              type: "float",
              size: Type.integer(8),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([215, 183]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.float(-123.45), {
              type: "float",
              size: Type.integer(8),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([183, 215]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("+0", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.float(0.0), {
              type: "float",
              size: Type.integer(8),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.float(0.0), {
              type: "float",
              size: Type.integer(8),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("-0", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.float(-0.0), {
              type: "float",
              size: Type.integer(8),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([128, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.float(-0.0), {
              type: "float",
              size: Type.integer(8),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 128]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });
      });

      describe("integer value", () => {
        describe("positive", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(123), {
              type: "float",
              size: Type.integer(8),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([87, 176]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(123), {
              type: "float",
              size: Type.integer(8),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([176, 87]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("negative", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(-123), {
              type: "float",
              size: Type.integer(8),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([215, 176]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(-123), {
              type: "float",
              size: Type.integer(8),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([176, 215]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("0", () => {
          it("big-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(0), {
              type: "float",
              size: Type.integer(8),
              unit: 2n,
              endianness: "big",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });

          it("little-endian", () => {
            const segment = Type.bitstringSegment(Type.integer(0), {
              type: "float",
              size: Type.integer(8),
              unit: 2n,
              endianness: "little",
            });

            const result = Bitstring.fromSegmentWithFloatValue(segment);

            const expected = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0, 0]),
              leftoverBitCount: 0,
              hex: null,
            };

            assert.deepStrictEqual(result, expected);
          });
        });
      });
    });
  });

  describe("fromSegmentWithIntegerValue()", () => {
    describe("integer type segment", () => {
      describe("integers within Number range", () => {
        describe("byte-aligned", () => {
          describe("stored in 8 bits", () => {
            describe("within 8 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 4 bits
                  const segment = Type.bitstringSegment(Type.integer(10), {
                    type: "integer",
                    size: Type.integer(4),
                    unit: 2n,
                    endianness: "big",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([10]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 4 bits
                  const segment = Type.bitstringSegment(Type.integer(10), {
                    type: "integer",
                    size: Type.integer(4),
                    unit: 2n,
                    endianness: "little",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([10]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 4 bits
                  const segment = Type.bitstringSegment(Type.integer(-246), {
                    type: "integer",
                    size: Type.integer(4),
                    unit: 2n,
                    endianness: "big",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([10]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 4 bits
                  const segment = Type.bitstringSegment(Type.integer(-246), {
                    type: "integer",
                    size: Type.integer(4),
                    unit: 2n,
                    endianness: "little",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([10]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });

            describe("outside 8 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 12 bits
                  const segment = Type.bitstringSegment(Type.integer(2730), {
                    type: "integer",
                    size: Type.integer(4),
                    unit: 2n,
                    endianness: "big",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([170]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 12 bits
                  const segment = Type.bitstringSegment(Type.integer(2730), {
                    type: "integer",
                    size: Type.integer(4),
                    unit: 2n,
                    endianness: "little",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([170]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 12 bits
                  const segment = Type.bitstringSegment(Type.integer(-62806), {
                    type: "integer",
                    size: Type.integer(4),
                    unit: 2n,
                    endianness: "big",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([170]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 12 bits
                  const segment = Type.bitstringSegment(Type.integer(-62806), {
                    type: "integer",
                    size: Type.integer(4),
                    unit: 2n,
                    endianness: "little",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([170]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });
          });

          describe("stored in 16 bits", () => {
            describe("within 16 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 12 bits
                  const segment = Type.bitstringSegment(Type.integer(2730), {
                    type: "integer",
                    size: Type.integer(8),
                    unit: 2n,
                    endianness: "big",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([10, 170]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 12 bits
                  const segment = Type.bitstringSegment(Type.integer(2730), {
                    type: "integer",
                    size: Type.integer(8),
                    unit: 2n,
                    endianness: "little",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([170, 10]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 12 bits
                  const segment = Type.bitstringSegment(Type.integer(-62806), {
                    type: "integer",
                    size: Type.integer(8),
                    unit: 2n,
                    endianness: "big",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([10, 170]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 12 bits
                  const segment = Type.bitstringSegment(Type.integer(-62806), {
                    type: "integer",
                    size: Type.integer(8),
                    unit: 2n,
                    endianness: "little",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([170, 10]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });

            describe("outside 16 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 20 bits
                  const segment = Type.bitstringSegment(Type.integer(879450), {
                    type: "integer",
                    size: Type.integer(8),
                    unit: 2n,
                    endianness: "big",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([107, 90]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 20 bits
                  const segment = Type.bitstringSegment(Type.integer(879450), {
                    type: "integer",
                    size: Type.integer(8),
                    unit: 2n,
                    endianness: "little",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([90, 107]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 20 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-15897766),
                    {
                      type: "integer",
                      size: Type.integer(8),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([107, 90]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 20 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-15897766),
                    {
                      type: "integer",
                      size: Type.integer(8),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([90, 107]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });
          });

          describe("stored in 32 bits", () => {
            describe("within 32 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 28 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(225139414),
                    {
                      type: "integer",
                      size: Type.integer(16),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([13, 107, 90, 214]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 28 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(225139414),
                    {
                      type: "integer",
                      size: Type.integer(16),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([214, 90, 107, 13]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 28 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-4069827882),
                    {
                      type: "integer",
                      size: Type.integer(16),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([13, 107, 90, 214]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 28 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-4069827882),
                    {
                      type: "integer",
                      size: Type.integer(16),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([214, 90, 107, 13]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });

            describe("outside 32 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 36 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(57635690165),
                    {
                      type: "integer",
                      size: Type.integer(16),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([107, 90, 214, 181]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 36 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(57635690165),
                    {
                      type: "integer",
                      size: Type.integer(16),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([181, 214, 90, 107]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 36 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-1041875937611),
                    {
                      type: "integer",
                      size: Type.integer(16),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([107, 90, 214, 181]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 36 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-1041875937611),
                    {
                      type: "integer",
                      size: Type.integer(16),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([181, 214, 90, 107]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });
          });

          describe("stored in 40 bits (more than 32 bits)", () => {
            describe("within 40 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 36 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(57635690165),
                    {
                      type: "integer",
                      size: Type.integer(20),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([13, 107, 90, 214, 181]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 36 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(57635690165),
                    {
                      type: "integer",
                      size: Type.integer(20),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([181, 214, 90, 107, 13]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 36 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-1041875937611),
                    {
                      type: "integer",
                      size: Type.integer(20),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([13, 107, 90, 214, 181]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 36 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-1041875937611),
                    {
                      type: "integer",
                      size: Type.integer(20),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([181, 214, 90, 107, 13]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });

            describe("outside 40 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 44 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(14754736682413),
                    {
                      type: "integer",
                      size: Type.integer(20),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([107, 90, 214, 181, 173]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 44 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(14754736682413),
                    {
                      type: "integer",
                      size: Type.integer(20),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([173, 181, 214, 90, 107]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 44 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-266720240028243),
                    {
                      type: "integer",
                      size: Type.integer(20),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([107, 90, 214, 181, 173]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("big-endian", () => {
                  // 44 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-266720240028243),
                    {
                      type: "integer",
                      size: Type.integer(20),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([173, 181, 214, 90, 107]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });
          });
        });

        describe("non-byte-aligned", () => {
          describe("stored in 4 bits", () => {
            describe("within 4 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 2 bits
                  const segment = Type.bitstringSegment(Type.integer(2), {
                    type: "integer",
                    size: Type.integer(2),
                    unit: 2n,
                    endianness: "big",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([32]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 2 bits
                  const segment = Type.bitstringSegment(Type.integer(2), {
                    type: "integer",
                    size: Type.integer(2),
                    unit: 2n,
                    endianness: "little",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([32]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 2 bits
                  const segment = Type.bitstringSegment(Type.integer(-254), {
                    type: "integer",
                    size: Type.integer(2),
                    unit: 2n,
                    endianness: "big",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([32]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 2 bits
                  const segment = Type.bitstringSegment(Type.integer(-254), {
                    type: "integer",
                    size: Type.integer(2),
                    unit: 2n,
                    endianness: "little",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([32]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });

            describe("outside 4 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 6 bits
                  const segment = Type.bitstringSegment(Type.integer(58), {
                    type: "integer",
                    size: Type.integer(2),
                    unit: 2n,
                    endianness: "big",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([160]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 6 bits
                  const segment = Type.bitstringSegment(Type.integer(58), {
                    type: "integer",
                    size: Type.integer(2),
                    unit: 2n,
                    endianness: "little",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([160]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 6 bits
                  const segment = Type.bitstringSegment(Type.integer(-198), {
                    type: "integer",
                    size: Type.integer(2),
                    unit: 2n,
                    endianness: "big",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([160]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 6 bits
                  const segment = Type.bitstringSegment(Type.integer(-198), {
                    type: "integer",
                    size: Type.integer(2),
                    unit: 2n,
                    endianness: "little",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([160]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });
          });

          describe("stored in 12 bits", () => {
            describe("within 12 bits range", () => {
              describe("positive", () => {
                // 10 bits
                it("big-endian", () => {
                  const segment = Type.bitstringSegment(Type.integer(682), {
                    type: "integer",
                    size: Type.integer(6),
                    unit: 2n,
                    endianness: "big",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([42, 160]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 10 bits
                  const segment = Type.bitstringSegment(Type.integer(682), {
                    type: "integer",
                    size: Type.integer(6),
                    unit: 2n,
                    endianness: "little",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([170, 32]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 10 bits
                  const segment = Type.bitstringSegment(Type.integer(-64854), {
                    type: "integer",
                    size: Type.integer(6),
                    unit: 2n,
                    endianness: "big",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([42, 160]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 10 bits
                  const segment = Type.bitstringSegment(Type.integer(-64854), {
                    type: "integer",
                    size: Type.integer(6),
                    unit: 2n,
                    endianness: "little",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([170, 32]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });

            describe("outside 12 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 14 bits
                  const segment = Type.bitstringSegment(Type.integer(10922), {
                    type: "integer",
                    size: Type.integer(6),
                    unit: 2n,
                    endianness: "big",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([170, 160]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 14 bits
                  const segment = Type.bitstringSegment(Type.integer(10922), {
                    type: "integer",
                    size: Type.integer(6),
                    unit: 2n,
                    endianness: "little",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([170, 160]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 14 bits
                  const segment = Type.bitstringSegment(Type.integer(-54614), {
                    type: "integer",
                    size: Type.integer(6),
                    unit: 2n,
                    endianness: "big",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([170, 160]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 14 bits
                  const segment = Type.bitstringSegment(Type.integer(-54614), {
                    type: "integer",
                    size: Type.integer(6),
                    unit: 2n,
                    endianness: "little",
                  });

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([170, 160]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });
          });

          describe("stored in 28 bits", () => {
            describe("within 28 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 26 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(47625645),
                    {
                      type: "integer",
                      size: Type.integer(14),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([45, 107, 90, 208]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 26 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(47625645),
                    {
                      type: "integer",
                      size: Type.integer(14),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([173, 181, 214, 32]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 26 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-4247341651),
                    {
                      type: "integer",
                      size: Type.integer(14),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([45, 107, 90, 208]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 26 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-4247341651),
                    {
                      type: "integer",
                      size: Type.integer(14),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([173, 181, 214, 32]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });

            describe("outside 28 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 30 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(900557658),
                    {
                      type: "integer",
                      size: Type.integer(14),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([90, 214, 181, 160]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 30 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(900557658),
                    {
                      type: "integer",
                      size: Type.integer(14),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([90, 107, 173, 80]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 30 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-3394409638),
                    {
                      type: "integer",
                      size: Type.integer(14),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([90, 214, 181, 160]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 30 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-3394409638),
                    {
                      type: "integer",
                      size: Type.integer(14),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([90, 107, 173, 80]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });
          });

          describe("stored in 44 bits (more than 32 bits)", () => {
            describe("within 44 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  const segment = Type.bitstringSegment(
                    // 42 bits
                    Type.integer(3121194298202),
                    {
                      type: "integer",
                      size: Type.integer(22),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([45, 107, 90, 214, 181, 160]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  const segment = Type.bitstringSegment(
                    // 42 bits
                    Type.integer(3121194298202),
                    {
                      type: "integer",
                      size: Type.integer(22),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([90, 107, 173, 181, 214, 32]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 42 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-278353782412454),
                    {
                      type: "integer",
                      size: Type.integer(22),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([45, 107, 90, 214, 181, 160]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 42 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-278353782412454),
                    {
                      type: "integer",
                      size: Type.integer(22),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([90, 107, 173, 181, 214, 32]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });

            describe("outside 44 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 46 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(49939108771245),
                    {
                      type: "integer",
                      size: Type.integer(22),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([214, 181, 173, 107, 90, 208]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 46 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(49939108771245),
                    {
                      type: "integer",
                      size: Type.integer(22),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([173, 181, 214, 90, 107, 208]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  const segment = Type.bitstringSegment(
                    // 46 bits
                    Type.integer(-231535867939411),
                    {
                      type: "integer",
                      size: Type.integer(22),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([214, 181, 173, 107, 90, 208]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  const segment = Type.bitstringSegment(
                    // 46 bits
                    Type.integer(-231535867939411),
                    {
                      type: "integer",
                      size: Type.integer(22),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([173, 181, 214, 90, 107, 208]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });
          });
        });
      });

      describe("integers outside Number range", () => {
        describe("byte-aligned", () => {
          describe("stored in 64 bits", () => {
            describe("within 64 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 60 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(966966423218645850n),
                    {
                      type: "integer",
                      size: Type.integer(32),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      13, 107, 90, 214, 181, 173, 107, 90,
                    ]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 60 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(966966423218645850n),
                    {
                      type: "integer",
                      size: Type.integer(32),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      90, 107, 173, 181, 214, 90, 107, 13,
                    ]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 60 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-17479777650490905766n),
                    {
                      type: "integer",
                      size: Type.integer(32),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      13, 107, 90, 214, 181, 173, 107, 90,
                    ]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 60 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-17479777650490905766n),
                    {
                      type: "integer",
                      size: Type.integer(32),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      90, 107, 173, 181, 214, 90, 107, 13,
                    ]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });

            describe("outside 64 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 68 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(247543404343973337814n),
                    {
                      type: "integer",
                      size: Type.integer(32),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      107, 90, 214, 181, 173, 107, 90, 214,
                    ]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 68 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(247543404343973337814n),
                    {
                      type: "integer",
                      size: Type.integer(32),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      214, 90, 107, 173, 181, 214, 90, 107,
                    ]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 68 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-4474823078525671875882n),
                    {
                      type: "integer",
                      size: Type.integer(32),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      107, 90, 214, 181, 173, 107, 90, 214,
                    ]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 68 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-4474823078525671875882n),
                    {
                      type: "integer",
                      size: Type.integer(32),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      214, 90, 107, 173, 181, 214, 90, 107,
                    ]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });
          });

          describe("stored in 72 bits", () => {
            describe("within 72 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 68 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(247543404343973337814n),
                    {
                      type: "integer",
                      size: Type.integer(36),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      13, 107, 90, 214, 181, 173, 107, 90, 214,
                    ]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 68 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(247543404343973337814n),
                    {
                      type: "integer",
                      size: Type.integer(36),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      214, 90, 107, 173, 181, 214, 90, 107, 13,
                    ]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 68 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-4474823078525671875882n),
                    {
                      type: "integer",
                      size: Type.integer(36),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      13, 107, 90, 214, 181, 173, 107, 90, 214,
                    ]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 68 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-4474823078525671875882n),
                    {
                      type: "integer",
                      size: Type.integer(36),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      214, 90, 107, 173, 181, 214, 90, 107, 13,
                    ]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });

            describe("outside 72 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 76 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(63371111512057174480565n),
                    {
                      type: "integer",
                      size: Type.integer(36),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      107, 90, 214, 181, 173, 107, 90, 214, 181,
                    ]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 76 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(63371111512057174480565n),
                    {
                      type: "integer",
                      size: Type.integer(36),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      181, 214, 90, 107, 173, 181, 214, 90, 107,
                    ]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 76 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-1145554708102572000225611n),
                    {
                      type: "integer",
                      size: Type.integer(36),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      107, 90, 214, 181, 173, 107, 90, 214, 181,
                    ]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 76 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-1145554708102572000225611n),
                    {
                      type: "integer",
                      size: Type.integer(36),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      181, 214, 90, 107, 173, 181, 214, 90, 107,
                    ]),
                    leftoverBitCount: 0,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });
          });
        });

        describe("non-byte-aligned", () => {
          describe("stored in 68 bits", () => {
            describe("within 68 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 66 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(61885851085993334453n),
                    {
                      type: "integer",
                      size: Type.integer(34),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      53, 173, 107, 90, 214, 181, 173, 107, 80,
                    ]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 66 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(61885851085993334453n),
                    {
                      type: "integer",
                      size: Type.integer(34),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      181, 214, 90, 107, 173, 181, 214, 90, 48,
                    ]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 66 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-4660480631783651879243n),
                    {
                      type: "integer",
                      size: Type.integer(34),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      53, 173, 107, 90, 214, 181, 173, 107, 80,
                    ]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 66 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-4660480631783651879243n),
                    {
                      type: "integer",
                      size: Type.integer(34),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      181, 214, 90, 107, 173, 181, 214, 90, 48,
                    ]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });

            describe("outside 68 bits range", () => {
              describe("positive", () => {
                it("big-endian", () => {
                  // 70 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(990173617375893351258n),
                    {
                      type: "integer",
                      size: Type.integer(34),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      90, 214, 181, 173, 107, 90, 214, 181, 160,
                    ]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 70 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(990173617375893351258n),
                    {
                      type: "integer",
                      size: Type.integer(34),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      90, 107, 173, 181, 214, 90, 107, 173, 80,
                    ]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });

              describe("negative", () => {
                it("big-endian", () => {
                  // 70 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-3732192865493751862438n),
                    {
                      type: "integer",
                      size: Type.integer(34),
                      unit: 2n,
                      endianness: "big",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      90, 214, 181, 173, 107, 90, 214, 181, 160,
                    ]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });

                it("little-endian", () => {
                  // 70 bits
                  const segment = Type.bitstringSegment(
                    Type.integer(-3732192865493751862438n),
                    {
                      type: "integer",
                      size: Type.integer(34),
                      unit: 2n,
                      endianness: "little",
                    },
                  );

                  const result = Bitstring.fromSegmentWithIntegerValue(segment);

                  const expected = {
                    type: "bitstring",
                    text: null,
                    bytes: new Uint8Array([
                      90, 107, 173, 181, 214, 90, 107, 173, 80,
                    ]),
                    leftoverBitCount: 4,
                    hex: null,
                  };

                  assert.deepStrictEqual(result, expected);
                });
              });
            });
          });
        });
      });
    });

    it("utf8 type segment", () => {
      const segment = Type.bitstringSegment(Type.integer(97), {
        type: "utf8",
      });

      const result = Bitstring.fromSegmentWithIntegerValue(segment);

      const expected = {
        type: "bitstring",
        text: "a",
        bytes: null,
        leftoverBitCount: 0,
        hex: null,
      };

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("fromSegmentWithStringValue()", () => {
    describe("binary type segment", () => {
      describe("ASCII", () => {
        it("without size or unit specified", () => {
          const segment = Type.bitstringSegment(Type.string("abc"), {
            type: "binary",
          });

          const result = Bitstring.fromSegmentWithStringValue(segment);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: "abc",
            bytes: null,
            leftoverBitCount: 0,
            hex: null,
          });
        });

        it("with size * unit matching the complete string", () => {
          const segment = Type.bitstringSegment(Type.string("abc"), {
            type: "binary",
            size: Type.integer(3),
            unit: 8,
          });

          const result = Bitstring.fromSegmentWithStringValue(segment);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: "abc",
            bytes: null,
            leftoverBitCount: 0,
            hex: null,
          });
        });

        it("with size * unit matching part of the string but complete bytes", () => {
          const segment = Type.bitstringSegment(Type.string("abc"), {
            type: "binary",
            size: Type.integer(2),
            unit: 8,
          });

          const result = Bitstring.fromSegmentWithStringValue(segment);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([97, 98]),
            leftoverBitCount: 0,
            hex: null,
          });
        });

        it("with leftover bits, size * unit taking up 1 byte", () => {
          const segment = Type.bitstringSegment(Type.string("abc"), {
            type: "binary",
            size: Type.integer(3),
            unit: 2,
          });

          const result = Bitstring.fromSegmentWithStringValue(segment);
          const expectedBytes = new Uint8Array([96]);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: expectedBytes,
            leftoverBitCount: 6,
            hex: null,
          });
        });

        it("with leftover bits, size * unit taking up 2 bytes", () => {
          const segment = Type.bitstringSegment(Type.string("abc"), {
            type: "binary",
            size: Type.integer(7),
            unit: 2,
          });

          const result = Bitstring.fromSegmentWithStringValue(segment);
          const expectedBytes = new Uint8Array([97, 96]);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: expectedBytes,
            leftoverBitCount: 6,
            hex: null,
          });
        });

        it("with leftover bits, size * unit taking up 3 bytes", () => {
          const segment = Type.bitstringSegment(Type.string("abcdef"), {
            type: "binary",
            size: Type.integer(11),
            unit: 2,
          });

          const result = Bitstring.fromSegmentWithStringValue(segment);
          const expectedBytes = new Uint8Array([97, 98, 96]);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: expectedBytes,
            leftoverBitCount: 6,
            hex: null,
          });
        });

        it("with leftover bits, size * unit taking up 10 (many) bytes", () => {
          const segment = Type.bitstringSegment(Type.string("abcdefghijklmn"), {
            type: "binary",
            size: Type.integer(39),
            unit: 2,
          });

          const result = Bitstring.fromSegmentWithStringValue(segment);

          const expectedBytes = new Uint8Array([
            97, 98, 99, 100, 101, 102, 103, 104, 105, 104,
          ]);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: expectedBytes,
            leftoverBitCount: 6,
            hex: null,
          });
        });
      });

      describe("Unicode", () => {
        it("without size or unit specified", () => {
          const segment = Type.bitstringSegment(Type.string("全息图"), {
            type: "binary",
          });

          const result = Bitstring.fromSegmentWithStringValue(segment);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: "全息图",
            bytes: null,
            leftoverBitCount: 0,
            hex: null,
          });
        });

        it("with size * unit matching the complete string", () => {
          const segment = Type.bitstringSegment(Type.string("全息图"), {
            type: "binary",
            size: Type.integer(9),
            unit: 8,
          });

          const result = Bitstring.fromSegmentWithStringValue(segment);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: "全息图",
            bytes: null,
            leftoverBitCount: 0,
            hex: null,
          });
        });

        it("with size * unit matching part of the string but complete bytes, and on char boundaries", () => {
          const segment = Type.bitstringSegment(Type.string("全息图"), {
            type: "binary",
            size: Type.integer(6),
            unit: 8,
          });

          const result = Bitstring.fromSegmentWithStringValue(segment);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([229, 133, 168, 230, 129, 175]),
            leftoverBitCount: 0,
            hex: null,
          });
        });

        it("with size * unit matching part of the string but complete bytes, and on not on char boundaries", () => {
          const segment = Type.bitstringSegment(Type.string("全息图"), {
            type: "binary",
            size: Type.integer(5),
            unit: 8,
          });

          const result = Bitstring.fromSegmentWithStringValue(segment);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([229, 133, 168, 230, 129]),
            leftoverBitCount: 0,
            hex: null,
          });
        });

        it("with leftover bits, size * unit taking up 1 byte", () => {
          const segment = Type.bitstringSegment(Type.string("全息图"), {
            type: "binary",
            size: Type.integer(3),
            unit: 2,
          });

          const result = Bitstring.fromSegmentWithStringValue(segment);
          const expectedBytes = new Uint8Array([228]);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: expectedBytes,
            leftoverBitCount: 6,
            hex: null,
          });
        });

        it("with leftover bits, size * unit taking up 2 bytes", () => {
          const segment = Type.bitstringSegment(Type.string("全息图"), {
            type: "binary",
            size: Type.integer(7),
            unit: 2,
          });

          const result = Bitstring.fromSegmentWithStringValue(segment);
          const expectedBytes = new Uint8Array([229, 132]);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: expectedBytes,
            leftoverBitCount: 6,
            hex: null,
          });
        });

        it("with leftover bits, size * unit taking up 3 bytes", () => {
          const segment = Type.bitstringSegment(Type.string("全息图"), {
            type: "binary",
            size: Type.integer(11),
            unit: 2,
          });

          const result = Bitstring.fromSegmentWithStringValue(segment);
          const expectedBytes = new Uint8Array([229, 133, 168]);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: expectedBytes,
            leftoverBitCount: 6,
            hex: null,
          });
        });

        it("with leftover bits, size * unit taking up 10 (many) bytes", () => {
          const segment = Type.bitstringSegment(
            Type.string("全息图全息图全息图"),
            {
              type: "binary",
              size: Type.integer(39),
              unit: 2,
            },
          );

          const result = Bitstring.fromSegmentWithStringValue(segment);

          const expectedBytes = new Uint8Array([
            229, 133, 168, 230, 129, 175, 229, 155, 190, 228,
          ]);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: expectedBytes,
            leftoverBitCount: 6,
            hex: null,
          });
        });
      });
    });
  });

  it("fromText()", () => {
    const result = Bitstring.fromText("Hologram");

    const expected = {
      type: "bitstring",
      text: "Hologram",
      bytes: null,
      leftoverBitCount: 0,
      hex: null,
    };

    assert.deepStrictEqual(result, expected);
  });

  describe("isEmpty()", () => {
    describe("empty", () => {
      it("with text field", () => {
        const bitstring = Type.bitstring("");
        bitstring.bytes = null;

        assert.isTrue(Bitstring.isEmpty(bitstring));
      });

      it("with bytes field", () => {
        const bitstring = Type.bitstring([]);
        bitstring.text = null;

        assert.isTrue(Bitstring.isEmpty(bitstring));
      });
    });

    describe("non-empty", () => {
      it("with text field", () => {
        const bitstring = Type.bitstring("abc");
        bitstring.bytes = null;

        assert.isFalse(Bitstring.isEmpty(bitstring));
      });

      it("with bytes field", () => {
        const bitstring = Type.bitstring([1, 0, 1]);
        bitstring.text = null;

        assert.isFalse(Bitstring.isEmpty(bitstring));
      });
    });
  });

  describe("isPrintableCodePoint()", () => {
    it("code point in range 0x20..0x7E", () => {
      assert.isTrue(Bitstring.isPrintableCodePoint(40));
    });

    it("code point not in range 0x20..0x7E", () => {
      assert.isFalse(Bitstring.isPrintableCodePoint(128));
    });

    it("code point in range 0xA0..0xD7FF", () => {
      assert.isTrue(Bitstring.isPrintableCodePoint(170));
    });

    it("code point not in range 0xA0..0xD7FF", () => {
      assert.isFalse(Bitstring.isPrintableCodePoint(55296));
    });

    it("code point in range 0xE000..0xFFFD", () => {
      assert.isTrue(Bitstring.isPrintableCodePoint(58000));
    });

    it("code point not in range 0xE000..0xFFFD", () => {
      assert.isFalse(Bitstring.isPrintableCodePoint(65534));
    });

    it("code point in range 0x10000..0x10FFFF", () => {
      assert.isTrue(Bitstring.isPrintableCodePoint(66000));
    });

    it("code point not in range 0x10000..0x10FFFF", () => {
      assert.isFalse(Bitstring.isPrintableCodePoint(1114112));
    });

    it("one of special printable chars", () => {
      assert.isTrue(Bitstring.isPrintableCodePoint(10));
    });

    it("not one of special printable chars", () => {
      assert.isFalse(Bitstring.isPrintableCodePoint(14));
    });
  });

  describe("isPrintableText()", () => {
    it("empty text", () => {
      assert.isTrue(Bitstring.isPrintableText(Type.bitstring("")));
    });

    it("ASCII text", () => {
      assert.isTrue(Bitstring.isPrintableText(Type.bitstring("abc")));
    });

    it("Unicode text (Chinese)", () => {
      assert.isTrue(Bitstring.isPrintableText(Type.bitstring("全息图")));
    });

    it("with non-printable character", () => {
      // \x01 is not printable
      assert.isFalse(Bitstring.isPrintableText(Type.bitstring("a\x01b")));
    });

    it("with invalid UTF-8 sequence", () => {
      const bitstring = Bitstring.fromBytes([255, 255]);
      assert.isFalse(Bitstring.isPrintableText(bitstring));
    });

    it("with leftover bits", () => {
      // prettier-ignore
      const bits = [
        0, 1, 1, 0, 0, 0, 0, 1, // "a"
        0, 1, 1, 0, 0, 0, 1, 0, // "b"
        1, 0, 1
      ]

      const bitstring = Bitstring.fromBits(bits);

      assert.isFalse(Bitstring.isPrintableText(bitstring));
    });

    it("sets the text field if the bytes sequence is representable as text", () => {
      // "abc"
      const bitstring = Bitstring.fromBytes([97, 98, 99]);

      assert.isNull(bitstring.text);

      Bitstring.isPrintableText(bitstring);
      assert.equal(bitstring.text, "abc");
    });
  });

  describe("isText()", () => {
    describe("based on text field", () => {
      it("empty text", () => {
        const bitstring = Type.bitstring("");
        assert.isTrue(Bitstring.isText(bitstring));
      });

      it("ASCII text", () => {
        const bitstring = Type.bitstring("abc");
        assert.isTrue(Bitstring.isText(bitstring));
      });

      it("Unicode text", () => {
        const bitstring = Type.bitstring("全息图");
        assert.isTrue(Bitstring.isText(bitstring));
      });
    });

    describe("based on bytes field", () => {
      it("empty text", () => {
        const bitstring = Type.bitstring([]);
        assert.isTrue(Bitstring.isText(bitstring));
      });

      it("ASCII text", () => {
        const bitstring = Bitstring.fromBytes([97, 98, 99]);
        assert.isTrue(Bitstring.isText(bitstring));
      });

      it("Unicode text", () => {
        const bitstring = Bitstring.fromBytes([
          229, 133, 168, 230, 129, 175, 229, 155, 190,
        ]);

        assert.isTrue(Bitstring.isText(bitstring));
      });

      it("not bitstring", () => {
        const term = Type.integer(123);
        assert.isFalse(Bitstring.isText(term));
      });

      it("non-binary bitstring", () => {
        const bitstring = Type.bitstring([1, 0, 1]);
        assert.isFalse(Bitstring.isText(bitstring));
      });

      it("with invalid code point", () => {
        const bitstring = Bitstring.fromBytes([255]);
        assert.isFalse(Bitstring.isText(bitstring));
      });
    });
  });

  describe("isValidUtf8ContinuationByte()", () => {
    it("valid continuation byte (10xxxxxx pattern)", () => {
      assert.isTrue(Bitstring.isValidUtf8ContinuationByte(0x80)); // 10000000
      assert.isTrue(Bitstring.isValidUtf8ContinuationByte(0xbf)); // 10111111
    });

    it("invalid continuation byte (not 10xxxxxx pattern)", () => {
      assert.isFalse(Bitstring.isValidUtf8ContinuationByte(0x00)); // 00000000 (ASCII)
      assert.isFalse(Bitstring.isValidUtf8ContinuationByte(0x7f)); // 01111111 (ASCII)
      assert.isFalse(Bitstring.isValidUtf8ContinuationByte(0xc0)); // 11000000 (2-byte start)
      assert.isFalse(Bitstring.isValidUtf8ContinuationByte(0xff)); // 11111111 (invalid)
    });
  });

  describe("isValidUtf8CodePoint()", () => {
    it("valid codepoint", () => {
      assert.isTrue(Bitstring.isValidUtf8CodePoint(0x41, 1)); // ASCII 'A'
      assert.isTrue(Bitstring.isValidUtf8CodePoint(0xa9, 2)); // © (copyright)
      assert.isTrue(Bitstring.isValidUtf8CodePoint(0x20ac, 3)); // € (euro)
      assert.isTrue(Bitstring.isValidUtf8CodePoint(0x10348, 4)); // 𐍈 (Gothic letter)
      assert.isTrue(Bitstring.isValidUtf8CodePoint(0x10ffff, 4)); // Maximum valid Unicode
    });

    it("overlong encoding (codepoint too small for encoding length)", () => {
      // 'A' (0x41) must use 1 byte, not 2
      assert.isFalse(Bitstring.isValidUtf8CodePoint(0x41, 2));
      // 0x7FF requires 2 bytes, but attempting 3-byte encoding
      assert.isFalse(Bitstring.isValidUtf8CodePoint(0x7ff, 3));
      // 0xFFFF requires 3 bytes, but attempting 4-byte encoding
      assert.isFalse(Bitstring.isValidUtf8CodePoint(0xffff, 4));
    });

    it("UTF-16 surrogate (U+D800–U+DFFF)", () => {
      assert.isFalse(Bitstring.isValidUtf8CodePoint(0xd800, 3)); // Start of surrogate range
      assert.isFalse(Bitstring.isValidUtf8CodePoint(0xdc00, 3)); // Middle of surrogate range
      assert.isFalse(Bitstring.isValidUtf8CodePoint(0xdfff, 3)); // End of surrogate range
    });

    it("beyond Unicode range (> U+10FFFF)", () => {
      assert.isFalse(Bitstring.isValidUtf8CodePoint(0x110000, 4));
      assert.isFalse(Bitstring.isValidUtf8CodePoint(0x200000, 4));
    });
  });

  describe("maybeResolveHex()", () => {
    it("when hex field is already set", () => {
      const bitstring = Type.bitstring("Hologram");
      bitstring.hex = "already_set";

      Bitstring.maybeResolveHex(bitstring);

      assert.equal(bitstring.hex, "already_set");
    });

    it("for empty bitstring", () => {
      const bitstring = Type.bitstring("");

      Bitstring.maybeResolveHex(bitstring);

      assert.equal(bitstring.hex, "");
    });

    it("for non-empty bitstring", () => {
      const bitstring = Type.bitstring("Hologram");

      Bitstring.maybeResolveHex(bitstring);

      assert.equal(bitstring.hex, "486f6c6f6772616d");
    });
  });

  describe("maybeSetBytesFromText()", () => {
    it("sets bytes when bytes is null", () => {
      const bitstring = Type.bitstring("abc");

      Bitstring.maybeSetBytesFromText(bitstring);
      assert.deepStrictEqual(bitstring.bytes, new Uint8Array([97, 98, 99]));
    });

    it("does nothing when bytes is already set", () => {
      const bitstring = Type.bitstring("abc");

      const existingBytes = new Uint8Array([1, 2, 3]);
      bitstring.bytes = existingBytes;

      Bitstring.maybeSetBytesFromText(bitstring);
      assert.strictEqual(bitstring.bytes, existingBytes);
    });

    it("handles empty string", () => {
      const bitstring = Type.bitstring("");

      Bitstring.maybeSetBytesFromText(bitstring);
      assert.deepStrictEqual(bitstring.bytes, new Uint8Array([]));
    });

    it("handles Unicode characters", () => {
      const bitstring = Type.bitstring("全息图");

      Bitstring.maybeSetBytesFromText(bitstring);

      assert.deepStrictEqual(
        bitstring.bytes,
        new Uint8Array([229, 133, 168, 230, 129, 175, 229, 155, 190]),
      );
    });
  });

  describe("maybeSetTextFromBytes()", () => {
    it("does nothing when text is already set to a string", () => {
      const bitstring = Type.bitstring("existing text");
      bitstring.bytes = new Uint8Array([97, 98, 99]); // "abc"

      Bitstring.maybeSetTextFromBytes(bitstring);
      assert.equal(bitstring.text, "existing text");
    });

    it("does nothing when text is already set to false", () => {
      const bitstring = Bitstring.fromBytes([97, 98, 99]); // "abc"
      bitstring.text = false;

      Bitstring.maybeSetTextFromBytes(bitstring);
      assert.isFalse(bitstring.text);
    });

    it("sets text from valid UTF-8 bytes", () => {
      const bitstring = Bitstring.fromBytes([97, 98, 99]); // "abc"

      Bitstring.maybeSetTextFromBytes(bitstring);
      assert.equal(bitstring.text, "abc");
    });

    it("sets text to false for invalid UTF-8 bytes", () => {
      const bitstring = Bitstring.fromBytes([255, 255]); // Invalid UTF-8 sequence

      Bitstring.maybeSetTextFromBytes(bitstring);
      assert.isFalse(bitstring.text);
    });
  });

  describe("resolveSegmentSize()", () => {
    it("returns explicit size when size is specified", () => {
      const segment = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
        size: Type.integer(16),
      });

      assert.equal(Bitstring.resolveSegmentSize(segment), 16);
    });

    it("calculates size for binary segment with string value", () => {
      const segment = Type.bitstringSegment(Type.string("全息图"), {
        type: "binary",
      });

      assert.equal(Bitstring.resolveSegmentSize(segment), 9);
    });

    it("calculates size for binary segment with bitstring value having not null text field", () => {
      const segment = Type.bitstringSegment(Type.bitstring("全息图"), {
        type: "binary",
      });

      assert.equal(Bitstring.resolveSegmentSize(segment), 9);
    });

    it("calculates size for binary segment with bitstring value having null text field", () => {
      const segment = Type.bitstringSegment(Bitstring.fromBytes([97, 98, 99]), {
        type: "binary",
      });

      assert.equal(Bitstring.resolveSegmentSize(segment), 3);
    });

    it("returns 64 for float segments by default", () => {
      const segment = Type.bitstringSegment(Type.float(123.45), {
        type: "float",
      });

      assert.equal(Bitstring.resolveSegmentSize(segment), 64);
    });

    it("returns 8 for integer segments by default", () => {
      const segment = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
      });

      assert.equal(Bitstring.resolveSegmentSize(segment), 8);
    });

    it("returns null for segments of type that don't have default size", () => {
      const segment = Type.bitstringSegment(Type.bitstring("abc"), {
        type: "bitstring",
      });

      assert.isNull(Bitstring.resolveSegmentSize(segment));
    });
  });

  describe("resolveSegmentUnit()", () => {
    it("returns explicit unit when it is specified", () => {
      const segment = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
        unit: 16n,
      });

      assert.equal(Bitstring.resolveSegmentUnit(segment), 16);
    });

    it("returns 8 for binary segments by default", () => {
      const segment = Type.bitstringSegment(Type.bitstring("abc"), {
        type: "binary",
      });

      assert.equal(Bitstring.resolveSegmentUnit(segment), 8);
    });

    it("returns 1 for bitstring segments by default", () => {
      const segment = Type.bitstringSegment(Type.bitstring("abc"), {
        type: "bitstring",
      });

      assert.equal(Bitstring.resolveSegmentUnit(segment), 1);
    });

    it("returns 1 for float segments by default", () => {
      const segment = Type.bitstringSegment(Type.float(123.45), {
        type: "float",
      });

      assert.equal(Bitstring.resolveSegmentUnit(segment), 1);
    });

    it("returns 1 for integer segments by default", () => {
      const segment = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
      });

      assert.equal(Bitstring.resolveSegmentUnit(segment), 1);
    });
  });

  describe("serialize()", () => {
    it("empty bitstring", () => {
      const bitstring = Type.bitstring("");
      const result = Bitstring.serialize(bitstring);

      assert.equal(result, "b");
    });

    it("non-empty bitstring without leftover bits", () => {
      const bitstring = Type.bitstring("Hologram");
      const result = Bitstring.serialize(bitstring);

      assert.equal(result, "b0486f6c6f6772616d");
    });

    it("non-empty bitstring with leftover bits", () => {
      const bitstring = Bitstring.fromBytes([1, 52, 103]);
      bitstring.leftoverBitCount = 5;

      const result = Bitstring.serialize(bitstring);

      assert.equal(result, "b5013467");
    });
  });

  describe("takeChunk()", () => {
    describe("take entire bitstring", () => {
      it("when text-based", () => {
        const original = {
          type: "bitstring",
          text: "abc",
          bytes: null,
          leftoverBitCount: 0,
          hex: null,
        };

        const result = Bitstring.takeChunk(original, 0, 24);
        assert.strictEqual(result, original); // Should return exact same object
      });

      it("when byte-based", () => {
        const original = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([97, 98, 99]),
          leftoverBitCount: 0,
          hex: null,
        };

        const result = Bitstring.takeChunk(original, 0, 24);
        assert.strictEqual(result, original); // Should return exact same object
      });
    });

    describe("byte-aligned offset", () => {
      it("zero-length chunk", () => {
        const bitstring = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa, 0xbb]),
          leftoverBitCount: 0,
          hex: null,
        };

        const result = Bitstring.takeChunk(bitstring, 8, 0);

        assert.deepStrictEqual(result, {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([]),
          leftoverBitCount: 0,
          hex: null,
        });
      });

      describe("single-bit chunk", () => {
        it("taken from the first byte", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0x80]), // 10000000
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.takeChunk(bitstring, 0, 1);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0x80]), // 10000000
            leftoverBitCount: 1,
            hex: null,
          });
        });

        it("taken from non-first byte", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0x00, 0x80]), // 00000000, 10000000
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.takeChunk(bitstring, 8, 1);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0x80]), // 10000000
            leftoverBitCount: 1,
            hex: null,
          });
        });
      });

      describe("single-byte chunk", () => {
        it("without leftover bits", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([97, 98, 99]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.takeChunk(bitstring, 8, 8);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([98]),
            leftoverBitCount: 0,
            hex: null,
          });
        });

        it("with leftover bits", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xaa, 0xbb, 0xcc]), // 10101010, 10111011, 11001100
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.takeChunk(bitstring, 8, 4);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xb0]), // 10110000
            leftoverBitCount: 4,
            hex: null,
          });
        });
      });

      describe("two-byte chunk", () => {
        it("without leftover bits", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd]), // 10101010, 10111011, 11001100, 11011101
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.takeChunk(bitstring, 8, 16);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xbb, 0xcc]), // 10111011, 11001100
            leftoverBitCount: 0,
            hex: null,
          });
        });

        it("with leftover bits", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xaa, 0xbb, 0xff]), // 10101010, 10111011, 11111111
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.takeChunk(bitstring, 8, 12);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xbb, 0xf0]), // 10111011, 11110000
            leftoverBitCount: 4,
            hex: null,
          });
        });
      });

      describe("rightmost bits chunk", () => {
        it("when there are no leftover bits", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xaa, 0xbb]), // 10101010, 10111011
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.takeChunk(bitstring, 8, 8);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xbb]), // 10111011
            leftoverBitCount: 0,
            hex: null,
          });
        });

        it("when there are leftover bits", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xaa, 0xb0]), // 10101010, 10110000
            leftoverBitCount: 4,
            hex: null,
          };

          const result = Bitstring.takeChunk(bitstring, 8, 4);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xb0]), // 10110000
            leftoverBitCount: 4,
            hex: null,
          });
        });
      });

      it("converts text to bytes when needed", () => {
        const bitstring = {
          type: "bitstring",
          text: "abc",
          bytes: null,
          leftoverBitCount: 0,
          hex: null,
        };

        const result = Bitstring.takeChunk(bitstring, 8, 8);

        assert.deepStrictEqual(result, {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([98]),
          leftoverBitCount: 0,
          hex: null,
        });
      });
    });

    describe("non-byte-aligned offset", () => {
      it("zero-length chunk", () => {
        const bitstring = {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([0xaa, 0xbb]),
          leftoverBitCount: 0,
          hex: null,
        };

        const result = Bitstring.takeChunk(bitstring, 4, 0);

        assert.deepStrictEqual(result, {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([]),
          leftoverBitCount: 0,
          hex: null,
        });
      });

      describe("single-bit chunk", () => {
        it("taken from the first byte", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0x08]), // 00001000
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.takeChunk(bitstring, 4, 1);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0x80]), // 10000000
            leftoverBitCount: 1,
            hex: null,
          });
        });

        it("taken from non-first byte", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0x00, 0x08]), // 00000000, 00001000
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.takeChunk(bitstring, 12, 1);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0x80]), // 10000000
            leftoverBitCount: 1,
            hex: null,
          });
        });
      });

      describe("single-byte chunk", () => {
        it("without leftover bits", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xaa, 0xbb, 0xcc]), // 10101010, 10111011, 11001100
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.takeChunk(bitstring, 4, 8);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xab]), // 10101011
            leftoverBitCount: 0,
            hex: null,
          });
        });

        it("with leftover bits", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xaa, 0xff]), // 10101010, 11111111
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.takeChunk(bitstring, 6, 4);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xb0]), // 10110000
            leftoverBitCount: 4,
            hex: null,
          });
        });
      });

      describe("two-byte chunk", () => {
        it("with leftover bits", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xaa, 0xbb, 0xcc]), // 10101010, 10111011, 11001100
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.takeChunk(bitstring, 4, 12);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xab, 0xb0]), // 10101011, 10110000
            leftoverBitCount: 4,
            hex: null,
          });
        });

        it("without leftover bits", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xaa, 0xbb, 0x5f]), // 10101010, 10111011, 01011111
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.takeChunk(bitstring, 4, 16);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xab, 0xb5]), // 10101011, 10110101
            leftoverBitCount: 0,
            hex: null,
          });
        });
      });

      describe("rightmost bits chunk", () => {
        it("when there are no leftover bits", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xaa, 0xfb]), // 10101010, 11111011
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.takeChunk(bitstring, 12, 4);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xb0]), // 10110000
            leftoverBitCount: 4,
            hex: null,
          });
        });

        it("when there are leftover bits", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xaa, 0xa8]), // 10101010, 10101000
            leftoverBitCount: 5,
            hex: null,
          };

          const result = Bitstring.takeChunk(bitstring, 10, 3);

          assert.deepStrictEqual(result, {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0xa0]), // 10100000
            leftoverBitCount: 3,
            hex: null,
          });
        });
      });

      it("converts text to bytes when needed", () => {
        const bitstring = {
          type: "bitstring",
          text: "abc", // 01100001, 01100010, 01100011
          bytes: null,
          leftoverBitCount: 0,
          hex: null,
        };

        const result = Bitstring.takeChunk(bitstring, 12, 8);

        assert.deepStrictEqual(result, {
          type: "bitstring",
          text: null,
          bytes: new Uint8Array([38]), // 00100110
          leftoverBitCount: 0,
          hex: null,
        });
      });
    });
  });

  describe("toCodepoints()", () => {
    describe("single codepoint", () => {
      it("$ (1 byte)", () => {
        const bitstring = Type.bitstring("$");
        const result = Bitstring.toCodepoints(bitstring);
        const expected = Type.list([Type.integer(36)]);

        assert.deepStrictEqual(result, expected);
      });

      it("£ (2 bytes)", () => {
        const bitstring = Type.bitstring("£");
        const result = Bitstring.toCodepoints(bitstring);
        const expected = Type.list([Type.integer(163)]);

        assert.deepStrictEqual(result, expected);
      });

      it("€ (3 bytes)", () => {
        const bitstring = Type.bitstring("€");
        const result = Bitstring.toCodepoints(bitstring);
        const expected = Type.list([Type.integer(8364)]);

        assert.deepStrictEqual(result, expected);
      });

      it("𐍈 (4 bytes)", () => {
        const bitstring = Type.bitstring("𐍈");
        const result = Bitstring.toCodepoints(bitstring);
        const expected = Type.list([Type.integer(66376)]);

        assert.deepStrictEqual(result, expected);
      });
    });

    it("multiple codepoints", () => {
      const bitstring = Type.bitstring("$£€𐍈");
      const result = Bitstring.toCodepoints(bitstring);

      const expected = Type.list([
        Type.integer(36),
        Type.integer(163),
        Type.integer(8364),
        Type.integer(66376),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("converts bytes to text when needed", () => {
      const bitstring = Bitstring.fromBytes([97, 98, 99]);
      const result = Bitstring.toCodepoints(bitstring);

      const expected = Type.list([
        Type.integer(97),
        Type.integer(98),
        Type.integer(99),
      ]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("toFloat()", () => {
    describe("big-endian", () => {
      describe("64-bit", () => {
        it("non-zero", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([64, 94, 221, 47, 26, 159, 190, 119]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "big");
          const expected = Type.float(123.456);

          assert.deepStrictEqual(result, expected);
        });

        it("signed zero, negative", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([128, 0, 0, 0, 0, 0, 0, 0]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "big");
          const expected = Type.float(-0.0);

          assert.deepStrictEqual(result, expected);
        });

        it("signed zero, positive", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0, 0, 0, 0, 0, 0, 0, 0]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "big");
          const expected = Type.float(+0.0);

          assert.deepStrictEqual(result, expected);
        });
      });

      describe("32-bit", () => {
        it("non-zero", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([66, 246, 233, 121]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "big");
          const expected = Type.float(123.45600128173828);

          assert.deepStrictEqual(result, expected);
        });

        it("signed zero, negative", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([128, 0, 0, 0]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "big");
          const expected = Type.float(-0.0);

          assert.deepStrictEqual(result, expected);
        });

        it("signed zero, positive", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0, 0, 0, 0]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "big");
          const expected = Type.float(+0.0);

          assert.deepStrictEqual(result, expected);
        });
      });

      describe("16-bit", () => {
        it("non-zero, normalized number", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([87, 183]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "big");
          const expected = Type.float(123.4375);

          assert.deepStrictEqual(result, expected);
        });

        it("non-zero, denormalized number", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0, 1]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "big");
          const expected = Type.float(5.960464477539063e-8);

          assert.deepStrictEqual(result, expected);
        });

        it("signed zero, negative", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([128, 0]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "big");
          const expected = Type.float(-0.0);

          assert.deepStrictEqual(result, expected);
        });

        it("signed zero, positive", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0, 0]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "big");
          const expected = Type.float(+0.0);

          assert.deepStrictEqual(result, expected);
        });
      });
    });

    describe("little-endian", () => {
      describe("64-bit", () => {
        it("non-zero", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([119, 190, 159, 26, 47, 221, 94, 64]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "little");
          const expected = Type.float(123.456);

          assert.deepStrictEqual(result, expected);
        });

        it("signed zero, negative", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0, 0, 0, 0, 0, 0, 0, 128]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "little");
          const expected = Type.float(-0.0);

          assert.deepStrictEqual(result, expected);
        });

        it("signed zero, positive", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0, 0, 0, 0, 0, 0, 0, 0]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "little");
          const expected = Type.float(+0.0);

          assert.deepStrictEqual(result, expected);
        });
      });

      describe("32-bit", () => {
        it("non-zero", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([121, 233, 246, 66]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "little");
          const expected = Type.float(123.45600128173828);

          assert.deepStrictEqual(result, expected);
        });

        it("signed zero, negative", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0, 0, 0, 128]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "little");
          const expected = Type.float(-0.0);

          assert.deepStrictEqual(result, expected);
        });

        it("signed zero, positive", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0, 0, 0, 0]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "little");
          const expected = Type.float(+0.0);

          assert.deepStrictEqual(result, expected);
        });
      });

      describe("16-bit", () => {
        it("non-zero, normalized number", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([183, 87]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "little");
          const expected = Type.float(123.4375);

          assert.deepStrictEqual(result, expected);
        });

        it("non-zero, denormalized number", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([1, 0]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "little");
          const expected = Type.float(5.960464477539063e-8);

          assert.deepStrictEqual(result, expected);
        });

        it("signed zero, negative", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0, 128]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "little");
          const expected = Type.float(-0.0);

          assert.deepStrictEqual(result, expected);
        });

        it("signed zero, positive", () => {
          const bitstring = {
            type: "bitstring",
            text: null,
            bytes: new Uint8Array([0, 0]),
            leftoverBitCount: 0,
            hex: null,
          };

          const result = Bitstring.toFloat(bitstring, "little");
          const expected = Type.float(+0.0);

          assert.deepStrictEqual(result, expected);
        });
      });
    });
  });

  describe("toInteger()", () => {
    it("empty bitstring", () => {
      const bitstring = {
        type: "bitstring",
        text: null,
        bytes: new Uint8Array([]),
        leftoverBitCount: 0,
        hex: null,
      };

      const result = Bitstring.toInteger(bitstring, "signed", "big");
      const expected = Type.integer(0n);

      assert.deepStrictEqual(result, expected);
    });

    describe("without leftover bits", () => {
      describe("signed", () => {
        describe("big-endian", () => {
          it("1 byte", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa]), // 10101010
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "big");
            const expected = Type.integer(-86n);

            assert.deepStrictEqual(result, expected);
          });

          it("2 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb]), // 10101010, 10111011
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "big");
            const expected = Type.integer(-21829n);

            assert.deepStrictEqual(result, expected);
          });

          it("3 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc]), // 10101010, 10111011, 11001100
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "big");
            const expected = Type.integer(-5588020n);

            assert.deepStrictEqual(result, expected);
          });

          it("4 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd]), // 10101010, 10111011, 11001100, 11011101
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "big");
            const expected = Type.integer(-1430532899n);

            assert.deepStrictEqual(result, expected);
          });

          it("5 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd, 0xee]), // 10101010, 10111011, 11001100, 11011101, 11101110
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "big");
            const expected = Type.integer(-366216421906n);

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("little-endian", () => {
          it("1 byte", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa]), // 10101010
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "little");
            const expected = Type.integer(-86n);

            assert.deepStrictEqual(result, expected);
          });

          it("2 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb]), // 10101010, 10111011
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "little");
            const expected = Type.integer(-17494n);

            assert.deepStrictEqual(result, expected);
          });

          it("3 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc]), // 10101010, 10111011, 11001100
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "little");
            const expected = Type.integer(-3359830n);

            assert.deepStrictEqual(result, expected);
          });

          it("4 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd]), // 10101010, 10111011, 11001100, 11011101
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "little");
            const expected = Type.integer(-573785174n);

            assert.deepStrictEqual(result, expected);
          });

          it("5 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd, 0xee]), // 10101010, 10111011, 11001100, 11011101, 11101110
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "little");
            const expected = Type.integer(-73588229206n);

            assert.deepStrictEqual(result, expected);
          });
        });
      });

      describe("unsigned", () => {
        describe("big-endian", () => {
          it("1 byte", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa]), // 10101010
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "big");
            const expected = Type.integer(170n);

            assert.deepStrictEqual(result, expected);
          });

          it("2 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb]), // 10101010, 10111011
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "big");
            const expected = Type.integer(43707n);

            assert.deepStrictEqual(result, expected);
          });

          it("3 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc]), // 10101010, 10111011, 11001100
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "big");
            const expected = Type.integer(11189196n);

            assert.deepStrictEqual(result, expected);
          });

          it("4 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd]), // 10101010, 10111011, 11001100, 11011101
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "big");
            const expected = Type.integer(2864434397n);

            assert.deepStrictEqual(result, expected);
          });

          it("5 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd, 0xee]), // 10101010, 10111011, 11001100, 11011101, 11101110
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "big");
            const expected = Type.integer(733295205870n);

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("little-endian", () => {
          it("1 byte", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa]), // 10101010
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "little");

            const expected = Type.integer(170n);

            assert.deepStrictEqual(result, expected);
          });

          it("2 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb]), // 10101010, 10111011
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "little");

            const expected = Type.integer(48042n);

            assert.deepStrictEqual(result, expected);
          });

          it("3 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc]), // 10101010, 10111011, 11001100
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "little");

            const expected = Type.integer(13417386n);

            assert.deepStrictEqual(result, expected);
          });

          it("4 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd]), // 10101010, 10111011, 11001100, 11011101
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "little");

            const expected = Type.integer(3721182122n);

            assert.deepStrictEqual(result, expected);
          });

          it("5 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd, 0xee]), // 10101010, 10111011, 11001100, 11011101, 11101110
              leftoverBitCount: 0,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "little");

            const expected = Type.integer(1025923398570n);

            assert.deepStrictEqual(result, expected);
          });
        });
      });
    });

    describe("with leftover bits", () => {
      describe("signed", () => {
        describe("big-endian", () => {
          it("1 byte", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xe0]), // 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "big");
            const expected = Type.integer(-1n);

            assert.deepStrictEqual(result, expected);
          });

          it("2 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xe0]), // 10101010, 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "big");
            const expected = Type.integer(-681n);

            assert.deepStrictEqual(result, expected);
          });

          it("3 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xe0]), // 10101010, 10111011, 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "big");
            const expected = Type.integer(-174625n);

            assert.deepStrictEqual(result, expected);
          });

          it("4 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xe0]), // 10101010, 10111011, 11001100, 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "big");
            const expected = Type.integer(-44704153n);

            assert.deepStrictEqual(result, expected);
          });

          it("5 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd, 0xe0]), // 10101010, 10111011, 11001100, 11011101, 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "big");
            const expected = Type.integer(-11444263185n);

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("little-endian", () => {
          it("1 byte", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xe0]), // 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "little");
            const expected = Type.integer(-1n);

            assert.deepStrictEqual(result, expected);
          });

          it("2 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xe0]), // 10101010, 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "little");
            const expected = Type.integer(-86n);

            assert.deepStrictEqual(result, expected);
          });

          it("3 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xe0]), // 10101010, 10111011, 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "little");
            const expected = Type.integer(-17494n);

            assert.deepStrictEqual(result, expected);
          });

          it("4 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xe0]), // 10101010, 10111011, 11001100, 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "little");
            const expected = Type.integer(-3359830n);

            assert.deepStrictEqual(result, expected);
          });

          it("5 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd, 0xe0]), // 10101010, 10111011, 11001100, 11011101, 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "signed", "little");
            const expected = Type.integer(-573785174n);

            assert.deepStrictEqual(result, expected);
          });
        });
      });

      describe("unsigned", () => {
        describe("big-endian", () => {
          it("1 byte", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xe0]), // 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "big");
            const expected = Type.integer(7n);

            assert.deepStrictEqual(result, expected);
          });

          it("2 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xe0]), // 10101010, 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "big");
            const expected = Type.integer(1367n);

            assert.deepStrictEqual(result, expected);
          });

          it("3 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xe0]), // 10101010, 10111011, 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "big");
            const expected = Type.integer(349663n);

            assert.deepStrictEqual(result, expected);
          });

          it("4 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xe0]), // 10101010, 10111011, 11001100, 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "big");
            const expected = Type.integer(89513575n);

            assert.deepStrictEqual(result, expected);
          });

          it("5 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd, 0xe0]), // 10101010, 10111011, 11001100, 11011101, 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "big");
            const expected = Type.integer(22915475183n);

            assert.deepStrictEqual(result, expected);
          });
        });

        describe("little-endian", () => {
          it("1 byte", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xe0]), // 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "little");

            const expected = Type.integer(7n);

            assert.deepStrictEqual(result, expected);
          });

          it("2 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xe0]), // 10101010, 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "little");

            const expected = Type.integer(1962n);

            assert.deepStrictEqual(result, expected);
          });

          it("3 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xe0]), // 10101010, 10111011, 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "little");

            const expected = Type.integer(506794n);

            assert.deepStrictEqual(result, expected);
          });

          it("4 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xe0]), // 10101010, 10111011, 11001100, 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "little");

            const expected = Type.integer(130857898n);

            assert.deepStrictEqual(result, expected);
          });

          it("5 bytes", () => {
            const bitstring = {
              type: "bitstring",
              text: null,
              bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd, 0xe0]), // 10101010, 10111011, 11001100, 11011101, 11100000
              leftoverBitCount: 3,
              hex: null,
            };

            const result = Bitstring.toInteger(bitstring, "unsigned", "little");

            const expected = Type.integer(33785953194n);

            assert.deepStrictEqual(result, expected);
          });
        });
      });
    });
  });

  it("toText()", () => {
    const bitstring = Bitstring.fromBytes([97, 98, 99]);
    const result = Bitstring.toText(bitstring);

    assert.equal(bitstring.text, "abc");
    assert.equal(result, "abc");
  });

  describe("validateCodePoint()", () => {
    it("integer that is a valid code point", () => {
      // a = 97
      assert.isTrue(Bitstring.validateCodePoint(97));
    });

    it("integer that is not a valid code point", () => {
      // Max Unicode code point value is 1,114,112
      assert.isFalse(Bitstring.validateCodePoint(1114113));
    });

    it("bigint that is a valid code point", () => {
      // a = 97
      assert.isTrue(Bitstring.validateCodePoint(97n));
    });

    it("bigint that is not a valid code point", () => {
      // Max Unicode code point value is 1,114,112
      assert.isFalse(Bitstring.validateCodePoint(1114113n));
    });

    it("not an integer or a bigint", () => {
      assert.isFalse(Bitstring.validateCodePoint("abc"));
    });
  });

  // TODO: implement consistency tests
  describe("validateSegment()", () => {
    describe("binary segments", () => {
      it("validates binary segment with byte-aligned bitstring value", () => {
        const segment = Type.bitstringSegment(Type.bitstring("abc"), {
          type: "binary",
        });

        assert.isTrue(Bitstring.validateSegment(segment, 1));
      });

      it("rejects binary segment with non-byte-aligned bitstring value", () => {
        const segment = Type.bitstringSegment(
          {
            type: "bitstring",
            bytes: new Uint8Array([255]),
            leftoverBitCount: 4,
            hex: null,
          },
          {type: "binary"},
        );

        assertBoxedError(
          () => Bitstring.validateSegment(segment, 1),
          "ArgumentError",
          "construction of binary failed: segment 1 of type 'binary': the size of the value <<15::size(4)>> is not a multiple of the unit for the segment",
        );
      });

      it("validates binary segment with string value", () => {
        const segment = Type.bitstringSegment(Type.string("abc"), {
          type: "binary",
        });

        assert.isTrue(Bitstring.validateSegment(segment, 1));
      });

      it("rejects binary segment with float value", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "binary",
        });

        assertBoxedError(
          () => Bitstring.validateSegment(segment, 1),
          "ArgumentError",
          "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 123.45",
        );
      });

      it("rejects binary segment with integer value", () => {
        const segment = Type.bitstringSegment(Type.integer(123), {
          type: "binary",
        });

        assertBoxedError(
          () => Bitstring.validateSegment(segment, 1),
          "ArgumentError",
          "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 123",
        );
      });
    });

    describe("bitstring segments", () => {
      it("validates bitstring segment with bitstring value", () => {
        const segment = Type.bitstringSegment(Type.bitstring("abc"), {
          type: "bitstring",
        });

        assert.isTrue(Bitstring.validateSegment(segment, 1));
      });

      it("rejects bitstring segment with float value", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "bitstring",
        });

        assertBoxedError(
          () => Bitstring.validateSegment(segment, 1),
          "ArgumentError",
          "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 123.45",
        );
      });

      it("rejects bitstring segment with integer value", () => {
        const segment = Type.bitstringSegment(Type.integer(123), {
          type: "bitstring",
        });

        assertBoxedError(
          () => Bitstring.validateSegment(segment, 1),
          "ArgumentError",
          "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 123",
        );
      });

      it("rejects bitstring segment with size specified", () => {
        const segment = Type.bitstringSegment(Type.bitstring("abc"), {
          type: "bitstring",
          size: Type.integer(16),
        });

        assertBoxedError(
          () => Bitstring.validateSegment(segment, 1),
          "ArgumentError",
          `construction of binary failed: segment 1 of type 'integer': expected an integer but got: "abc"`,
        );
      });

      it("rejects bitstring segment with signedness specified", () => {
        const segment = Type.bitstringSegment(Type.bitstring("abc"), {
          type: "bitstring",
          signedness: "unsigned",
        });

        assertBoxedError(
          () => Bitstring.validateSegment(segment, 1),
          "ArgumentError",
          `construction of binary failed: segment 1 of type 'integer': expected an integer but got: "abc"`,
        );
      });
    });

    describe("float segments", () => {
      it("validates float segment with float value", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "float",
        });

        assert.isTrue(Bitstring.validateSegment(segment, 1));
      });

      it("validates float segment with integer value", () => {
        const segment = Type.bitstringSegment(Type.integer(123), {
          type: "float",
        });

        assert.isTrue(Bitstring.validateSegment(segment, 1));
      });

      it("validates float segment with variable pattern value", () => {
        const segment = Type.bitstringSegment(Type.variablePattern("abc"), {
          type: "float",
        });

        assert.isTrue(Bitstring.validateSegment(segment, 1));
      });

      it("rejects float segment with bitstring value", () => {
        const segment = Type.bitstringSegment(Type.bitstring("abc"), {
          type: "float",
        });

        assertBoxedError(
          () => Bitstring.validateSegment(segment, 1),
          "ArgumentError",
          `construction of binary failed: segment 1 of type 'float': expected a float or an integer but got: "abc"`,
        );
      });

      it("rejects float segment when unit is specified without size", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "float",
          unit: 2n,
        });

        assertBoxedError(
          () => Bitstring.validateSegment(segment, 1),
          "CompileError",
          "integer and float types require a size specifier if the unit specifier is given",
        );
      });

      it("validates float segment with valid bit size", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "float",
          size: Type.integer(32),
        });

        assert.isTrue(Bitstring.validateSegment(segment, 1));
      });

      it("rejects float segment with invalid bit size", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "float",
          size: Type.integer(24),
        });

        assertBoxedError(
          () => Bitstring.validateSegment(segment, 1),
          "ArgumentError",
          "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 123.45",
        );
      });
    });

    describe("integer segments", () => {
      it("validates integer segment with integer value", () => {
        const segment = Type.bitstringSegment(Type.integer(123), {
          type: "integer",
        });

        assert.isTrue(Bitstring.validateSegment(segment, 1));
      });

      it("validates integer segment with variable pattern value", () => {
        const segment = Type.bitstringSegment(Type.variablePattern("abc"), {
          type: "integer",
        });

        assert.isTrue(Bitstring.validateSegment(segment, 1));
      });

      it("rejects integer segment with float value", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "integer",
        });

        assertBoxedError(
          () => Bitstring.validateSegment(segment, 1),
          "ArgumentError",
          "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 123.45",
        );
      });
    });

    describe("UTF segments", () => {
      describe("utf8", () => {
        it("validates utf8 segment with integer value", () => {
          const segment = Type.bitstringSegment(Type.integer(97), {
            type: "utf8",
          });

          assert.isTrue(Bitstring.validateSegment(segment, 1));
        });

        it("rejects utf8 segment with float value", () => {
          const segment = Type.bitstringSegment(Type.float(123.45), {
            type: "utf8",
          });

          assertBoxedError(
            () => Bitstring.validateSegment(segment, 1),
            "ArgumentError",
            "construction of binary failed: segment 1 of type 'utf8': expected a non-negative integer encodable as utf8 but got: 123.45",
          );
        });

        it("rejects utf8 segment with size specified", () => {
          const segment = Type.bitstringSegment(Type.integer(97), {
            type: "utf8",
            size: Type.integer(16),
          });

          assertBoxedError(
            () => Bitstring.validateSegment(segment, 1),
            "ArgumentError",
            "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 97",
          );
        });

        it("rejects utf8 segment with unit specified", () => {
          const segment = Type.bitstringSegment(Type.integer(97), {
            type: "utf8",
            unit: 2n,
          });

          assertBoxedError(
            () => Bitstring.validateSegment(segment, 1),
            "ArgumentError",
            "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 97",
          );
        });

        it("rejects utf8 segment with signedness specified", () => {
          const segment = Type.bitstringSegment(Type.integer(97), {
            type: "utf8",
            signedness: "unsigned",
          });

          assertBoxedError(
            () => Bitstring.validateSegment(segment, 1),
            "ArgumentError",
            "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 97",
          );
        });
      });

      describe("utf16", () => {
        it("validates utf16 segment with integer value", () => {
          const segment = Type.bitstringSegment(Type.integer(97), {
            type: "utf16",
          });

          assert.isTrue(Bitstring.validateSegment(segment, 1));
        });

        it("rejects utf16 segment with float value", () => {
          const segment = Type.bitstringSegment(Type.float(123.45), {
            type: "utf16",
          });

          assertBoxedError(
            () => Bitstring.validateSegment(segment, 1),
            "ArgumentError",
            "construction of binary failed: segment 1 of type 'utf16': expected a non-negative integer encodable as utf16 but got: 123.45",
          );
        });

        it("rejects utf16 segment with size specified", () => {
          const segment = Type.bitstringSegment(Type.integer(97), {
            type: "utf16",
            size: Type.integer(16),
          });

          assertBoxedError(
            () => Bitstring.validateSegment(segment, 1),
            "ArgumentError",
            "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 97",
          );
        });

        it("rejects utf16 segment with unit specified", () => {
          const segment = Type.bitstringSegment(Type.integer(97), {
            type: "utf16",
            unit: 2n,
          });

          assertBoxedError(
            () => Bitstring.validateSegment(segment, 1),
            "ArgumentError",
            "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 97",
          );
        });

        it("rejects utf16 segment with signedness specified", () => {
          const segment = Type.bitstringSegment(Type.integer(97), {
            type: "utf16",
            signedness: "unsigned",
          });

          assertBoxedError(
            () => Bitstring.validateSegment(segment, 1),
            "ArgumentError",
            "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 97",
          );
        });
      });

      describe("utf32", () => {
        it("validates utf32 segment with integer value", () => {
          const segment = Type.bitstringSegment(Type.integer(97), {
            type: "utf32",
          });

          assert.isTrue(Bitstring.validateSegment(segment, 1));
        });

        it("rejects utf32 segment with float value", () => {
          const segment = Type.bitstringSegment(Type.float(123.45), {
            type: "utf32",
          });

          assertBoxedError(
            () => Bitstring.validateSegment(segment, 1),
            "ArgumentError",
            "construction of binary failed: segment 1 of type 'utf32': expected a non-negative integer encodable as utf32 but got: 123.45",
          );
        });

        it("rejects utf32 segment with size specified", () => {
          const segment = Type.bitstringSegment(Type.integer(97), {
            type: "utf32",
            size: Type.integer(16),
          });

          assertBoxedError(
            () => Bitstring.validateSegment(segment, 1),
            "ArgumentError",
            "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 97",
          );
        });

        it("rejects utf32 segment with unit specified", () => {
          const segment = Type.bitstringSegment(Type.integer(97), {
            type: "utf32",
            unit: 2n,
          });

          assertBoxedError(
            () => Bitstring.validateSegment(segment, 1),
            "ArgumentError",
            "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 97",
          );
        });

        it("rejects utf32 segment with signedness specified", () => {
          const segment = Type.bitstringSegment(Type.integer(97), {
            type: "utf32",
            signedness: "unsigned",
          });

          assertBoxedError(
            () => Bitstring.validateSegment(segment, 1),
            "ArgumentError",
            "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 97",
          );
        });
      });
    });
  });

  describe("getUtf8SequenceLength()", () => {
    it("returns 1 for 0x41 (ASCII)", () => {
      assert.equal(Bitstring.getUtf8SequenceLength(0x41), 1);
    });

    it("returns 2 for 0xC2 (2-byte leader)", () => {
      assert.equal(Bitstring.getUtf8SequenceLength(0xc2), 2);
    });

    it("returns 3 for 0xE0 (3-byte leader)", () => {
      assert.equal(Bitstring.getUtf8SequenceLength(0xe0), 3);
    });

    it("returns 4 for 0xF0 (4-byte leader)", () => {
      assert.equal(Bitstring.getUtf8SequenceLength(0xf0), 4);
    });

    it("returns false for 0xC0 (invalid: overlong encoding)", () => {
      assert.equal(Bitstring.getUtf8SequenceLength(0xc0), false);
    });

    it("returns false for 0xF5 (invalid: > U+10FFFF)", () => {
      assert.equal(Bitstring.getUtf8SequenceLength(0xf5), false);
    });

    it("returns false for 0x80 (invalid: continuation byte)", () => {
      assert.equal(Bitstring.getUtf8SequenceLength(0x80), false);
    });
  });
});
