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
  describe("buildSignedBigIntFromBitArray()", () => {
    it("0", () => {
      const bitArray = new Uint8Array([]);
      const result = Bitstring.buildSignedBigIntFromBitArray(bitArray);

      assert.equal(result, 0n);
    });

    it("0b0101010 == 42", () => {
      const bitArray = new Uint8Array([0, 1, 0, 1, 0, 1, 0]);
      const result = Bitstring.buildSignedBigIntFromBitArray(bitArray);

      assert.equal(result, 42n);
    });

    it("0b101010 == -22", () => {
      const bitArray = new Uint8Array([1, 0, 1, 0, 1, 0]);
      const result = Bitstring.buildSignedBigIntFromBitArray(bitArray);

      assert.equal(result, -22n);
    });

    it("0b0101010101010 == 2730", () => {
      const bitArray = new Uint8Array([0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]);
      const result = Bitstring.buildSignedBigIntFromBitArray(bitArray);

      assert.equal(result, 2730n);
    });

    it("0b101010101010 == -1366", () => {
      const bitArray = new Uint8Array([1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]);
      const result = Bitstring.buildSignedBigIntFromBitArray(bitArray);

      assert.equal(result, -1366n);
    });
  });

  describe("buildUnsignedBigIntFromBitArray()", () => {
    it("0", () => {
      const bitArray = new Uint8Array([]);
      const result = Bitstring.buildUnsignedBigIntFromBitArray(bitArray);

      assert.equal(result, 0n);
    });

    it("0b0101010 == 42", () => {
      const bitArray = new Uint8Array([0, 1, 0, 1, 0, 1, 0]);
      const result = Bitstring.buildUnsignedBigIntFromBitArray(bitArray);

      assert.equal(result, 42n);
    });

    it("0b101010 == 42", () => {
      const bitArray = new Uint8Array([1, 0, 1, 0, 1, 0]);
      const result = Bitstring.buildUnsignedBigIntFromBitArray(bitArray);

      assert.equal(result, 42n);
    });

    it("0b0101010101010 == 2730", () => {
      const bitArray = new Uint8Array([0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]);
      const result = Bitstring.buildUnsignedBigIntFromBitArray(bitArray);

      assert.equal(result, 2730n);
    });

    it("0b101010101010 == 2730", () => {
      const bitArray = new Uint8Array([1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]);
      const result = Bitstring.buildUnsignedBigIntFromBitArray(bitArray);

      assert.equal(result, 2730n);
    });
  });

  describe("fetchNextCodePointFromUtf8BitstringChunk()", () => {
    it("$ (1 byte)", () => {
      const bitArray = new Uint8Array([0, 0, 1, 0, 0, 1, 0, 0]);

      const result = Bitstring.fetchNextCodePointFromUtf8BitstringChunk(
        bitArray,
        0,
      );

      assert.deepStrictEqual(result, [Type.integer(36), 8]);
    });

    it("£ (2 bytes)", () => {
      // prettier-ignore
      const bitArray = new Uint8Array([
      1, 1, 0, 0, 0, 0, 1, 0,
      1, 0, 1, 0, 0, 0, 1, 1,
    ]);

      const result = Bitstring.fetchNextCodePointFromUtf8BitstringChunk(
        bitArray,
        0,
      );

      assert.deepStrictEqual(result, [Type.integer(163), 16]);
    });

    it("€ (3 bytes)", () => {
      // prettier-ignore
      const bitArray = new Uint8Array([
      1, 1, 1, 0, 0, 0, 1, 0,
      1, 0, 0, 0, 0, 0, 1, 0,
      1, 0, 1, 0, 1, 1, 0, 0,
    ]);

      const result = Bitstring.fetchNextCodePointFromUtf8BitstringChunk(
        bitArray,
        0,
      );

      assert.deepStrictEqual(result, [Type.integer(8364), 24]);
    });

    it("𐍈 (4 bytes)", () => {
      // prettier-ignore
      const bitArray = new Uint8Array([
      1, 1, 1, 1, 0, 0, 0, 0,
      1, 0, 0, 1, 0, 0, 0, 0,
      1, 0, 0, 0, 1, 1, 0, 1,
      1, 0, 0, 0, 1, 0, 0, 0,
    ]);

      const result = Bitstring.fetchNextCodePointFromUtf8BitstringChunk(
        bitArray,
        0,
      );

      assert.deepStrictEqual(result, [Type.integer(66376), 32]);
    });
  });

  // IMPORTANT!
  // Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/bitstring_test.exs
  // Always update both together.
  describe("from()", () => {
    describe("number and structure of segments", () => {
      it("builds empty bitstring without segments", () => {
        const result = Bitstring.from([]);

        const expected = {
          type: "bitstring",
          bits: new Uint8Array([]),
        };

        assert.deepStrictEqual(result, expected);
      });

      it("builds single-segment bitstring", () => {
        const segment = Type.bitstringSegment(Type.integer(1), {
          size: Type.integer(1),
          type: "integer",
          unit: 1n,
        });

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          bits: new Uint8Array([1]),
        };

        assert.deepStrictEqual(result, expected);
      });

      it("builds multiple-segment bitstring", () => {
        const segment = Type.bitstringSegment(Type.integer(1), {
          size: Type.integer(1),
          type: "integer",
          unit: 1n,
        });

        const result = Bitstring.from([segment, segment]);

        const expected = {
          type: "bitstring",
          bits: new Uint8Array([1, 1]),
        };

        assert.deepStrictEqual(result, expected);
      });

      it("nested segments are flattened", () => {
        const segment1 = Type.bitstringSegment(Type.bitstring([1, 1]), {
          type: "bitstring",
        });

        const segment2 = Type.bitstringSegment(
          Type.bitstring([
            Type.bitstringSegment(Type.bitstring([1, 0]), {type: "bitstring"}),
            Type.bitstringSegment(Type.bitstring([1]), {type: "bitstring"}),
            Type.bitstringSegment(Type.bitstring([1, 0]), {type: "bitstring"}),
          ]),
          {type: "bitstring"},
        );

        const segment3 = Type.bitstringSegment(Type.bitstring([1, 1]), {
          type: "bitstring",
        });

        const result = Bitstring.from([segment1, segment2, segment3]);

        const expected = {
          type: "bitstring",
          bits: new Uint8Array([1, 1, 1, 0, 1, 1, 0, 1, 1]),
        };

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("defaults", () => {
      it("for bitstring value", () => {
        const segment = Type.bitstringSegment(Type.bitstring([1, 0, 1, 0]), {
          type: "bitstring",
        });

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          bits: new Uint8Array([1, 0, 1, 0]),
        };

        assert.deepStrictEqual(result, expected);
      });

      it("for float value", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "float",
        });

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          // prettier-ignore
          bits: new Uint8Array([
                0, 1, 0, 0, 0, 0, 0, 0,
                0, 1, 0, 1, 1, 1, 1, 0,
                1, 1, 0, 1, 1, 1, 0, 0,
                1, 1, 0, 0, 1, 1, 0, 0,
                1, 1, 0, 0, 1, 1, 0, 0,
                1, 1, 0, 0, 1, 1, 0, 0,
                1, 1, 0, 0, 1, 1, 0, 0,
                1, 1, 0, 0, 1, 1, 0, 1
              ]),
        };

        assert.deepStrictEqual(result, expected);
      });

      it("for positive integer value that fits in 8 bits", () => {
        const segment = Type.bitstringSegment(Type.integer(170), {
          type: "integer",
        });

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          bits: new Uint8Array([1, 0, 1, 0, 1, 0, 1, 0]),
        };

        assert.deepStrictEqual(result, expected);
      });

      it("for negative integer value that fits in 8 bits", () => {
        const segment = Type.bitstringSegment(Type.integer(-22), {
          type: "integer",
        });

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          bits: new Uint8Array([1, 1, 1, 0, 1, 0, 1, 0]),
        };

        assert.deepStrictEqual(result, expected);
      });

      it("for positive integer value that fits in 12 bits", () => {
        const segment = Type.bitstringSegment(Type.integer(4010), {
          type: "integer",
        });

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          bits: new Uint8Array([1, 0, 1, 0, 1, 0, 1, 0]),
        };

        assert.deepStrictEqual(result, expected);
      });

      it("for negative integer value that fits in 12 bits", () => {
        const segment = Type.bitstringSegment(Type.integer(-86), {
          type: "integer",
        });

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          bits: new Uint8Array([1, 0, 1, 0, 1, 0, 1, 0]),
        };

        assert.deepStrictEqual(result, expected);
      });

      it("for string value", () => {
        const segment = Type.bitstringSegment(Type.string("全息图"), {
          type: "utf8",
        });

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          // prettier-ignore
          bits: new Uint8Array([
            1, 1, 1, 0, 0, 1, 0, 1,
            1, 0, 0, 0, 0, 1, 0, 1,
            1, 0, 1, 0, 1, 0, 0, 0,
            1, 1, 1, 0, 0, 1, 1, 0,
            1, 0, 0, 0, 0, 0, 0, 1,
            1, 0, 1, 0, 1, 1, 1, 1,
            1, 1, 1, 0, 0, 1, 0, 1,
            1, 0, 0, 1, 1, 0, 1, 1,
            1, 0, 1, 1, 1, 1, 1, 0
          ]),
        };

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("binary type modifier", () => {
      it("with bitstring value when number of bits is divisible by 8", () => {
        const segment = Type.bitstringSegment(
          Type.bitstring([1, 0, 1, 0, 1, 0, 1, 0]),
          {type: "binary"},
        );

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          bits: new Uint8Array([1, 0, 1, 0, 1, 0, 1, 0]),
        };

        assert.deepStrictEqual(result, expected);
      });

      it("with bitstring value when number of bits is not divisible by 8", () => {
        const segment = Type.bitstringSegment(Type.bitstring([1, 0, 1]), {
          type: "binary",
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'binary': the size of the value <<5::size(3)>> is not a multiple of the unit for the segment`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("with float value", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "binary",
        });

        const expectedMessage =
          "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 123.45";

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("with integer value", () => {
        const segment = Type.bitstringSegment(Type.integer(170), {
          type: "binary",
        });

        const expectedMessage =
          "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 170";

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("with string value", () => {
        const segment = Type.bitstringSegment(Type.string("全息图"), {
          type: "binary",
        });

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          // prettier-ignore
          bits: new Uint8Array([
            1, 1, 1, 0, 0, 1, 0, 1,
            1, 0, 0, 0, 0, 1, 0, 1,
            1, 0, 1, 0, 1, 0, 0, 0,
            1, 1, 1, 0, 0, 1, 1, 0,
            1, 0, 0, 0, 0, 0, 0, 1,
            1, 0, 1, 0, 1, 1, 1, 1,
            1, 1, 1, 0, 0, 1, 0, 1,
            1, 0, 0, 1, 1, 0, 1, 1,
            1, 0, 1, 1, 1, 1, 1, 0
          ]),
        };

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("bistring type modifier", () => {
      // Exactly the same as the defaults test for bitstring value.
      // it("with bitstring value")

      it("with float value", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "bitstring",
        });

        const expectedMessage =
          "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 123.45";

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("with integer value", () => {
        const segment = Type.bitstringSegment(Type.integer(170), {
          type: "bitstring",
        });

        const expectedMessage =
          "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 170";

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("with string value", () => {
        const segment = Type.bitstringSegment(Type.string("全息图"), {
          type: "bitstring",
        });

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          // prettier-ignore
          bits: new Uint8Array([
            1, 1, 1, 0, 0, 1, 0, 1,
            1, 0, 0, 0, 0, 1, 0, 1,
            1, 0, 1, 0, 1, 0, 0, 0,
            1, 1, 1, 0, 0, 1, 1, 0,
            1, 0, 0, 0, 0, 0, 0, 1,
            1, 0, 1, 0, 1, 1, 1, 1,
            1, 1, 1, 0, 0, 1, 0, 1,
            1, 0, 0, 1, 1, 0, 1, 1,
            1, 0, 1, 1, 1, 1, 1, 0
          ]),
        };

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("float type modifier", () => {
      it("with bitstring value", () => {
        const segment = Type.bitstringSegment(Type.bitstring([1, 0, 1]), {
          type: "float",
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'float': expected a float or an integer but got: <<5::size(3)>>`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      // Exactly the same as the defaults test for float value.
      // it("with float value")

      it("with integer value", () => {
        const segment = Type.bitstringSegment(
          Type.integer(1234567890123456789n),
          {
            type: "float",
          },
        );

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          // prettier-ignore
          bits: new Uint8Array([
                0, 1, 0, 0, 0, 0, 1, 1,
                1, 0, 1, 1, 0, 0, 0, 1,
                0, 0, 1, 0, 0, 0, 1, 0,
                0, 0, 0, 1, 0, 0, 0, 0,
                1, 1, 1, 1, 0, 1, 0, 0,
                0, 1, 1, 1, 1, 1, 0, 1,
                1, 1, 1, 0, 1, 0, 0, 1,
                1, 0, 0, 0, 0, 0, 0, 1
              ]),
        };

        assert.deepStrictEqual(result, expected);
      });

      it("with string value consisting of a single ASCI characters", () => {
        const segment = Type.bitstringSegment(Type.string("a"), {
          type: "float",
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'float': expected a float or an integer but got: "a"`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("with string value consisting of multiple ASCI characters", () => {
        const segment = Type.bitstringSegment(Type.string("abc"), {
          type: "float",
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'float': expected a float or an integer but got: "abc"`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });
    });

    describe("integer type modifier", () => {
      it("with bitstring value", () => {
        const segment = Type.bitstringSegment(Type.bitstring([1, 0, 1]), {
          type: "integer",
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'integer': expected an integer but got: <<5::size(3)>>`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("with float value", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "integer",
        });

        const expectedMessage =
          "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 123.45";

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      // Exactly the same as the defaults test for integer value.
      // it("with integer value")

      it("with string value consisting of a single ASCI characters", () => {
        const segment = Type.bitstringSegment(Type.string("a"), {
          type: "integer",
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'integer': expected an integer but got: "a"`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("with string value consisting of multiple ASCI characters", () => {
        const segment = Type.bitstringSegment(Type.string("abc"), {
          type: "integer",
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'integer': expected an integer but got: "abc"`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });
    });

    describe("signed signedness modifier", () => {
      it("with bitstring value", () => {
        const segment = Type.bitstringSegment(Type.bitstring([1, 0, 1, 0]), {
          type: "bitstring",
          signedness: "signed",
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'integer': expected an integer but got: <<10::size(4)>>`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("with float value", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "float",
          signedness: "signed",
        });

        const result = Bitstring.from([segment]);

        const expected = Bitstring.from([
          Type.bitstringSegment(Type.float(123.45), {type: "float"}),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("with integer value", () => {
        const segment = Type.bitstringSegment(Type.integer(123), {
          type: "integer",
          signedness: "signed",
        });

        const result = Bitstring.from([segment]);

        const expected = Bitstring.from([
          Type.bitstringSegment(Type.integer(123), {type: "integer"}),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("with string value", () => {
        const segment = Type.bitstringSegment(Type.string("abc"), {
          type: "utf8",
          signedness: "signed",
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'integer': expected an integer but got: "abc"`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });
    });

    describe("size modifier", () => {
      it("with bitstring value", () => {
        const segment = Type.bitstringSegment(Type.bitstring([1, 0, 1, 0]), {
          type: "bitstring",
          size: Type.integer(3),
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'integer': expected an integer but got: <<10::size(4)>>`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      // TODO: update once 16-bit float bitstring segments get implemented in Hologram
      it("with float value when size * unit results in 16, 32 or 64", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "float",
          size: Type.integer(16),
        });

        assert.throw(
          () => Bitstring.from([segment]),
          HologramInterpreterError,
          "16-bit float bitstring segments are not yet implemented in Hologram",
        );
      });

      it("with float value when size * unit doesn't result in 16, 32 or 64", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "float",
          size: Type.integer(7),
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'integer': expected an integer but got: 123.45`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("with integer value", () => {
        // 183 == 0b10110111
        // 23 == 0b10111
        const segment = Type.bitstringSegment(Type.integer(183), {
          type: "integer",
          size: Type.integer(5),
        });

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          bits: new Uint8Array([1, 0, 1, 1, 1]),
        };

        assert.deepStrictEqual(result, expected);
      });

      it("with string value", () => {
        const segment = Type.bitstringSegment(Type.string("abc"), {
          type: "utf8",
          size: Type.integer(7),
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'integer': expected an integer but got: "abc"`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });
    });

    describe("unit modifier (with size modifier)", () => {
      it("with bitstring value", () => {
        const segment = Type.bitstringSegment(
          Type.bitstring([1, 0, 1, 0, 1, 0, 1, 0]),
          {
            type: "bitstring",
            size: Type.integer(3),
            unit: 2n,
          },
        );

        const expectedMessage = `construction of binary failed: segment 1 of type 'integer': expected an integer but got: <<170>>`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      // TODO: update once 16-bit float bitstring segments get implemented in Hologram
      it("with float value when size * unit results in 16, 32 or 64", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "float",
          size: Type.integer(8),
          unit: 2n,
        });

        assert.throw(
          () => Bitstring.from([segment]),
          HologramInterpreterError,
          "16-bit float bitstring segments are not yet implemented in Hologram",
        );
      });

      it("with float value when size * unit doesn't result in 16, 32 or 64", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "float",
          size: Type.integer(7),
          unit: 2n,
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'integer': expected an integer but got: 123.45`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("with integer value", () => {
        // 170 == 0b10101010
        // 42 == 0b101010
        const segment = Type.bitstringSegment(Type.integer(170), {
          type: "integer",
          size: Type.integer(3),
          unit: 2n,
        });

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          bits: new Uint8Array([1, 0, 1, 0, 1, 0]),
        };

        assert.deepStrictEqual(result, expected);
      });

      it("with string value", () => {
        const segment = Type.bitstringSegment(Type.string("abc"), {
          type: "utf8",
          size: Type.integer(7),
          unit: 2n,
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'integer': expected an integer but got: "abc"`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });
    });

    describe("unsigned signedness modifier", () => {
      it("with bitstring value", () => {
        const segment = Type.bitstringSegment(Type.bitstring([1, 0, 1, 0]), {
          type: "bitstring",
          signedness: "unsigned",
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'integer': expected an integer but got: <<10::size(4)>>`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("with float value", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "float",
          signedness: "unsigned",
        });

        const result = Bitstring.from([segment]);

        const expected = Bitstring.from([
          Type.bitstringSegment(Type.float(123.45), {type: "float"}),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("with integer value", () => {
        const segment = Type.bitstringSegment(Type.integer(123), {
          type: "integer",
          signedness: "unsigned",
        });

        const result = Bitstring.from([segment]);

        const expected = Bitstring.from([
          Type.bitstringSegment(Type.integer(123), {type: "integer"}),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("with string value", () => {
        const segment = Type.bitstringSegment(Type.string("abc"), {
          type: "utf8",
          signedness: "unsigned",
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'integer': expected an integer but got: "abc"`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });
    });

    describe("utf8 type modifier", () => {
      it("with bitstring value", () => {
        // ?a == 97 == 0b01100001
        const segment = Type.bitstringSegment(
          Type.bitstring([0, 1, 1, 0, 0, 0, 0, 1]),
          {
            type: "utf8",
          },
        );

        const expectedMessage = `construction of binary failed: segment 1 of type 'utf8': expected a non-negative integer encodable as utf8 but got: "a"`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("with float value", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "utf8",
        });

        const expectedMessage =
          "construction of binary failed: segment 1 of type 'utf8': expected a non-negative integer encodable as utf8 but got: 123.45";

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("with integer value that is a valid Unicode code point", () => {
        const segment = Type.bitstringSegment(Type.integer(20840), {
          type: "utf8",
        });

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          // prettier-ignore
          bits: new Uint8Array([
                1, 1, 1, 0, 0, 1, 0, 1,
                1, 0, 0, 0, 0, 1, 0, 1,
                1, 0, 1, 0, 1, 0, 0, 0
              ]),
        };

        assert.deepStrictEqual(result, expected);
      });

      it("with integer value that is not a valid Unicode code point", () => {
        const segment = Type.bitstringSegment(Type.integer(1114113), {
          type: "utf8",
        });

        const expectedMessage =
          "construction of binary failed: segment 1 of type 'utf8': expected a non-negative integer encodable as utf8 but got: 1114113";

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      // Exactly the same as the defaults test for string value.
      // it("with literal string value")

      it("with runtime string value", () => {
        const segment = Type.bitstringSegment(Type.bitstring("abc"), {
          type: "utf8",
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'utf8': expected a non-negative integer encodable as utf8 but got: "abc"`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });
    });

    describe("utf16 type modifier", () => {
      it("with bitstring value", () => {
        // ?a == 97 == 0b01100001
        const segment = Type.bitstringSegment(
          Type.bitstring([0, 1, 1, 0, 0, 0, 0, 1]),
          {
            type: "utf16",
          },
        );

        const expectedMessage = `construction of binary failed: segment 1 of type 'utf16': expected a non-negative integer encodable as utf16 but got: "a"`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("with integer value that is a valid Unicode code point", () => {
        const segment = Type.bitstringSegment(Type.integer(20840), {
          type: "utf16",
        });

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          // prettier-ignore
          bits: new Uint8Array([
                0, 1, 0, 1, 0, 0, 0, 1,
                0, 1, 1, 0, 1, 0, 0, 0
              ]),
        };

        assert.deepStrictEqual(result, expected);
      });

      it("with integer value that is not a valid Unicode code point", () => {
        const segment = Type.bitstringSegment(Type.integer(1114113), {
          type: "utf16",
        });

        const expectedMessage =
          "construction of binary failed: segment 1 of type 'utf16': expected a non-negative integer encodable as utf16 but got: 1114113";

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("with literal string value", () => {
        const segment = Type.bitstringSegment(Type.string("全息图"), {
          type: "utf16",
        });

        const result = Bitstring.from([segment]);

        const expected = {
          type: "bitstring",
          // prettier-ignore
          bits: new Uint8Array([
            0, 1, 0, 1, 0, 0, 0, 1,
            0, 1, 1, 0, 1, 0, 0, 0,
            0, 1, 1, 0, 0, 0, 0, 0,
            0, 1, 1, 0, 1, 1, 1, 1,
            0, 1, 0, 1, 0, 1, 1, 0,
            1, 1, 1, 1, 1, 1, 1, 0
          ]),
        };

        assert.deepStrictEqual(result, expected);
      });

      it("with runtime string value", () => {
        const segment = Type.bitstringSegment(Type.bitstring("abc"), {
          type: "utf16",
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'utf16': expected a non-negative integer encodable as utf16 but got: "abc"`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });
    });

    describe("utf32 type modifier", () => {
      it("with runtime string value", () => {
        const segment = Type.bitstringSegment(Type.bitstring("abc"), {
          type: "utf32",
        });

        const expectedMessage = `construction of binary failed: segment 1 of type 'utf32': expected a non-negative integer encodable as utf32 but got: "abc"`;

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });
    });

    describe("values of not supported data types", () => {
      it("atom values are not supported", () => {
        const segment = Type.bitstringSegment(Type.atom("abc"), {
          type: "integer",
        });

        const expectedMessage =
          "construction of binary failed: segment 1 of type 'integer': expected an integer but got: :abc";

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("list values are not supported", () => {
        const segment = Type.bitstringSegment(
          Type.list([Type.integer(1), Type.integer(2)]),
          {type: "integer"},
        );

        const expectedMessage =
          "construction of binary failed: segment 1 of type 'integer': expected an integer but got: [1, 2]";

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });

      it("tuple values are not supported", () => {
        const segment = Type.bitstringSegment(
          Type.tuple([Type.integer(1), Type.integer(2)]),
          {type: "integer"},
        );

        const expectedMessage =
          "construction of binary failed: segment 1 of type 'integer': expected an integer but got: {1, 2}";

        assertBoxedError(
          () => Bitstring.from([segment]),
          "ArgumentError",
          expectedMessage,
        );
      });
    });

    describe("with empty string segments", () => {
      it("the last segment is an empty string with utf8 modifier", () => {
        // <<1, "">>
        const result = Type.bitstring([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
          Type.bitstringSegment(Type.string(""), {type: "utf8"}),
        ]);

        const expected = Type.bitstring([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("the last segment is an empty string with binary modifier", () => {
        // <<1, "">>
        const result = Type.bitstring([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
          Type.bitstringSegment(Type.string(""), {type: "binary"}),
        ]);

        const expected = Type.bitstring([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("the first segment is an empty string with utf8 modifier", () => {
        // <<"", 1>>
        const result = Type.bitstring([
          Type.bitstringSegment(Type.string(""), {type: "utf8"}),
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
        ]);

        const expected = Type.bitstring([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("the first segment is an empty string with binary modifier", () => {
        // <<"", 1>>
        const result = Type.bitstring([
          Type.bitstringSegment(Type.string(""), {type: "binary"}),
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
        ]);

        const expected = Type.bitstring([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("the middle segment is an empty string with utf8 modifier", () => {
        // <<1, "", 2>>
        const result = Type.bitstring([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
          Type.bitstringSegment(Type.string(""), {type: "utf8"}),
          Type.bitstringSegment(Type.integer(2), {type: "integer"}),
        ]);

        const expected = Type.bitstring([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
          Type.bitstringSegment(Type.integer(2), {type: "integer"}),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("the middle segment is an empty string with binary modifier", () => {
        // <<1, "", 2>>
        const result = Type.bitstring([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
          Type.bitstringSegment(Type.string(""), {type: "binary"}),
          Type.bitstringSegment(Type.integer(2), {type: "integer"}),
        ]);

        const expected = Type.bitstring([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
          Type.bitstringSegment(Type.integer(2), {type: "integer"}),
        ]);

        assert.deepStrictEqual(result, expected);
      });
    });
  });

  describe("isPrintableCodePoint()", () => {
    it("codePoint in range 0x20..0x7E", () => {
      assert.isTrue(Bitstring.isPrintableCodePoint(40));
    });

    it("codePoint not in range 0x20..0x7E", () => {
      assert.isFalse(Bitstring.isPrintableCodePoint(128));
    });

    it("codePoint in range 0xA0..0xD7FF", () => {
      assert.isTrue(Bitstring.isPrintableCodePoint(170));
    });

    it("codePoint not in range 0xA0..0xD7FF", () => {
      assert.isFalse(Bitstring.isPrintableCodePoint(55296));
    });

    it("codePoint in range 0xE000..0xFFFD", () => {
      assert.isTrue(Bitstring.isPrintableCodePoint(58000));
    });

    it("codePoint not in range 0xE000..0xFFFD", () => {
      assert.isFalse(Bitstring.isPrintableCodePoint(65534));
    });

    it("codePoint in range 0x10000..0x10FFFF", () => {
      assert.isTrue(Bitstring.isPrintableCodePoint(66000));
    });

    it("codePoint not in range 0x10000..0x10FFFF", () => {
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

    it("Unicode text", () => {
      assert.isTrue(Bitstring.isPrintableText(Type.bitstring("全息图")));
    });

    it("non-binary", () => {
      assert.isFalse(Bitstring.isPrintableText(Type.bitstring([1, 0, 1])));
    });

    it("with code point that is not printable", () => {
      const bitstring = Type.bitstring([
        // ?a = 97
        Type.bitstringSegment(Type.integer(97), {type: "integer"}),
        Type.bitstringSegment(Type.integer(2), {type: "integer"}),
        // ?b = 98
        Type.bitstringSegment(Type.integer(98), {type: "integer"}),
      ]);

      assert.isFalse(Bitstring.isPrintableText(bitstring));
    });

    it("with invalid code point", () => {
      const bitstring = Type.bitstring([
        Type.bitstringSegment(Type.integer(255), {type: "integer"}),
      ]);

      assert.isFalse(Bitstring.isPrintableText(bitstring));
    });
  });

  describe("isText()", () => {
    it("empty text", () => {
      assert.isTrue(Bitstring.isText(Type.bitstring("")));
    });

    it("ASCII text", () => {
      assert.isTrue(Bitstring.isText(Type.bitstring("abc")));
    });

    it("Unicode text", () => {
      assert.isTrue(Bitstring.isText(Type.bitstring("全息图")));
    });

    it("non-binary", () => {
      assert.isFalse(Bitstring.isText(Type.bitstring([1, 0, 1])));
    });

    it("with invalid code point", () => {
      const bitstring = Type.bitstring([
        Type.bitstringSegment(Type.integer(255), {type: "integer"}),
      ]);

      assert.isFalse(Bitstring.isText(bitstring));
    });
  });

  describe("merge()", () => {
    it("no bitstrings", () => {
      assert.deepStrictEqual(Bitstring.merge([]), Type.bitstring([]));
    });

    it("single bitstring", () => {
      const bitstring = Type.bitstring([1, 0, 1]);
      const result = Bitstring.merge([bitstring]);

      assert.deepStrictEqual(result, bitstring);
    });

    it("multiple bitstrings", () => {
      const bitstring1 = Type.bitstring([1, 1, 0]);
      const bitstring2 = Type.bitstring([1, 0, 1]);
      const bitstring3 = Type.bitstring([0, 1, 1]);

      const result = Bitstring.merge([bitstring1, bitstring2, bitstring3]);
      const expected = Type.bitstring([1, 1, 0, 1, 0, 1, 0, 1, 1]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("resolveSegmentSize()", () => {
    it("size in float segment is specified", () => {
      const segment = Type.bitstringSegment(Type.float(1.23), {
        type: "float",
        size: Type.integer(7),
      });

      assert.equal(Bitstring.resolveSegmentSize(segment), 7n);
    });

    it("size in float segment is not specified", () => {
      const segment = Type.bitstringSegment(Type.float(1.23), {type: "float"});

      assert.equal(Bitstring.resolveSegmentSize(segment), 64n);
    });

    it("size in integer segment is specified", () => {
      const segment = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
        size: Type.integer(7),
      });

      assert.equal(Bitstring.resolveSegmentSize(segment), 7n);
    });

    it("size in integer segment is not specified", () => {
      const segment = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
      });

      assert.equal(Bitstring.resolveSegmentSize(segment), 8n);
    });

    it("size in segment of type other than float or integer is specified", () => {
      const segment = Type.bitstringSegment(Type.string("abc"), {
        type: "binary",
        size: Type.integer(7),
      });

      assert.throw(
        () => Bitstring.resolveSegmentSize(segment),
        HologramInterpreterError,
        "resolving binary segment size is not yet implemented in Hologram",
      );
    });

    it("size in segment of type other than float or integer is not specified", () => {
      const segment = Type.bitstringSegment(Type.string("abc"), {
        type: "binary",
      });

      assert.throw(
        () => Bitstring.resolveSegmentSize(segment),
        HologramInterpreterError,
        "resolving binary segment size is not yet implemented in Hologram",
      );
    });
  });

  describe("resolveSegmentUnit()", () => {
    it("unit in binary segment is specified", () => {
      const segment = Type.bitstringSegment(Type.bitstring("abc"), {
        type: "binary",
        unit: 3n,
      });

      assert.equal(Bitstring.resolveSegmentUnit(segment), 3n);
    });

    it("unit in binary segment is not specified", () => {
      const segment = Type.bitstringSegment(Type.bitstring("abc"), {
        type: "binary",
      });

      assert.equal(Bitstring.resolveSegmentUnit(segment), 8n);
    });

    it("unit in float segment is specified", () => {
      const segment = Type.bitstringSegment(Type.float(1.23), {
        type: "float",
        unit: 3n,
      });

      assert.equal(Bitstring.resolveSegmentUnit(segment), 3n);
    });

    it("unit in float segment is not specified", () => {
      const segment = Type.bitstringSegment(Type.float(1.23), {type: "float"});

      assert.equal(Bitstring.resolveSegmentUnit(segment), 1n);
    });

    it("unit in integer segment is specified", () => {
      const segment = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
        unit: 3n,
      });

      assert.equal(Bitstring.resolveSegmentUnit(segment), 3n);
    });

    it("unit in integer segment is not specified", () => {
      const segment = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
      });

      assert.equal(Bitstring.resolveSegmentUnit(segment), 1n);
    });

    it("unit in segment of type other than binary, float or integer is specified", () => {
      const segment = Type.bitstringSegment(Type.bitstring([1, 0, 1]), {
        type: "bitstring",
        unit: 3n,
      });

      assert.throw(
        () => Bitstring.resolveSegmentUnit(segment),
        HologramInterpreterError,
        "resolving bitstring segment unit is not yet implemented in Hologram",
      );
    });

    it("unit in segment of type other than binary, float or integer is not specified", () => {
      const segment = Type.bitstringSegment(Type.bitstring([1, 0, 1]), {
        type: "bitstring",
      });

      assert.throw(
        () => Bitstring.resolveSegmentUnit(segment),
        HologramInterpreterError,
        "resolving bitstring segment unit is not yet implemented in Hologram",
      );
    });
  });

  describe("toText()", () => {
    it("converts the bitstring to UTF-8 text if the number of its bits is divisible by 8", () => {
      const bitstring = Type.bitstring("全息图");
      const result = Bitstring.toText(bitstring);

      assert.equal(result, "全息图");
    });

    it("raises error when the number of bits in the bitstring is not divisible by 8", () => {
      const bitstring = Type.bitstring([1, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 1]);

      assert.throw(
        () => Bitstring.toText(bitstring),
        HologramInterpreterError,
        "number of bits must be divisible by 8, got 12 bits",
      );
    });
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

  // The function is tested implicitely in bitstring and match operator consistency tests.
  describe("validateSegment()", () => {
    it("valid segment", () => {
      const segment = Type.bitstringSegment(Type.float(123.45), {
        type: "float",
        size: Type.integer(64),
      });

      assert.isTrue(Bitstring.validateSegment(segment, 1));
    });

    it("invalid segment", () => {
      const segment = Type.bitstringSegment(Type.float(123.45), {
        type: "float",
        size: Type.integer(8),
      });

      assertBoxedError(
        () => Bitstring.validateSegment(segment, 1),
        "ArgumentError",
        "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 123.45",
      );
    });
  });
});
