"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Bitstring2 from "../../assets/js/bitstring2.mjs";
import HologramInterpreterError from "../../assets/js/errors/interpreter_error.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Bitstring2", () => {
  describe("calculateSegmentBitCount()", () => {
    it("calculates bit count when size and unit are explicitly specified", () => {
      const segment = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
        size: Type.integer(16),
        unit: 2n,
      });

      assert.equal(Bitstring2.calculateSegmentBitCount(segment), 32);
    });

    it("calculates bit count when size and unit are not specified", () => {
      const segment = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
      });

      assert.equal(Bitstring2.calculateSegmentBitCount(segment), 8);
    });
  });

  describe("concatSegments()", () => {
    it("single string binary segment", () => {
      const result = Bitstring2.concatSegments([
        Type.bitstringSegment(Type.string("Hologram"), {type: "binary"}),
      ]);

      const expected = {
        type: "bitstring2",
        text: "Hologram",
        bytes: null,
        leftoverBitCount: 0,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("multiple string binary segments", () => {
      const result = Bitstring2.concatSegments([
        Type.bitstringSegment(Type.string("Holo"), {type: "binary"}),
        Type.bitstringSegment(Type.string("gram"), {type: "binary"}),
      ]);

      const expected = {
        type: "bitstring2",
        text: "Hologram",
        bytes: null,
        leftoverBitCount: 0,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("single string utf8 segment", () => {
      const result = Bitstring2.concatSegments([
        Type.bitstringSegment(Type.string("Hologram"), {type: "utf8"}),
      ]);

      const expected = {
        type: "bitstring2",
        text: "Hologram",
        bytes: null,
        leftoverBitCount: 0,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("multiple string utf8 segments", () => {
      const result = Bitstring2.concatSegments([
        Type.bitstringSegment(Type.string("Holo"), {type: "utf8"}),
        Type.bitstringSegment(Type.string("gram"), {type: "utf8"}),
      ]);

      const expected = {
        type: "bitstring2",
        text: "Hologram",
        bytes: null,
        leftoverBitCount: 0,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("string binary and utf8 segments", () => {
      const result = Bitstring2.concatSegments([
        Type.bitstringSegment(Type.string("Holo"), {type: "binary"}),
        Type.bitstringSegment(Type.string("gram"), {type: "utf8"}),
      ]);

      const expected = {
        type: "bitstring2",
        text: "Hologram",
        bytes: null,
        leftoverBitCount: 0,
      };

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("fromBits()", () => {
    it("empty", () => {
      const result = Bitstring2.fromBits([]);

      const expected = {
        type: "bitstring2",
        text: null,
        bytes: new Uint8Array(0),
        leftoverBitCount: 0,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("single byte, byte-aligned", () => {
      const result = Bitstring2.fromBits([1, 0, 1, 0, 1, 0, 1, 0]);

      const expected = {
        type: "bitstring2",
        text: null,
        bytes: new Uint8Array([170]),
        leftoverBitCount: 0,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("single byte, not byte-aligned", () => {
      const result = Bitstring2.fromBits([1, 0, 1, 0]);

      const expected = {
        type: "bitstring2",
        text: null,
        bytes: new Uint8Array([160]),
        leftoverBitCount: 4,
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
        type: "bitstring2",
        text: null,
        bytes: new Uint8Array([170, 85]),
        leftoverBitCount: 0,
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
        type: "bitstring2",
        text: null,
        bytes: new Uint8Array([170, 85, 160]),
        leftoverBitCount: 4,
      };

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("fromBytes()", () => {
    it("creates bitstring from Uint8Array", () => {
      const bytes = new Uint8Array([1, 2, 3]);
      const result = Bitstring2.fromBytes(bytes);

      const expected = {
        type: "bitstring2",
        text: null,
        bytes: bytes,
        leftoverBitCount: 0,
      };

      assert.deepStrictEqual(result, expected);
      assert.strictEqual(result.bytes, bytes);
    });

    it("creates bitstring from regular array", () => {
      const bytes = [1, 2, 3];
      const result = Bitstring2.fromBytes(bytes);

      const expected = {
        type: "bitstring2",
        text: null,
        bytes: new Uint8Array([1, 2, 3]),
        leftoverBitCount: 0,
      };

      assert.deepStrictEqual(result, expected);
    });

    it("handles empty array", () => {
      const result = Bitstring2.fromBytes([]);

      const expected = {
        type: "bitstring2",
        text: null,
        bytes: new Uint8Array([]),
        leftoverBitCount: 0,
      };

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("fromFloatSegment()", () => {
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([64, 94, 220, 204, 204, 204, 204, 205]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([205, 204, 204, 204, 204, 220, 94, 64]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([192, 94, 220, 204, 204, 204, 204, 205]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([205, 204, 204, 204, 204, 220, 94, 192]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0, 0, 0, 0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0, 0, 0, 0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([128, 0, 0, 0, 0, 0, 0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0, 0, 0, 0, 128]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([64, 94, 192, 0, 0, 0, 0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0, 0, 192, 94, 64]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([192, 94, 192, 0, 0, 0, 0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0, 0, 192, 94, 192]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0, 0, 0, 0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0, 0, 0, 0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([66, 246, 230, 102]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([102, 230, 246, 66]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([194, 246, 230, 102]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([102, 230, 246, 194]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([128, 0, 0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 128]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([66, 246, 0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0, 246, 66]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([194, 246, 0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0, 246, 194]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0, 0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([87, 183]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([183, 87]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([215, 183]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([183, 215]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([128, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 128]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([87, 176]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([176, 87]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([215, 176]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([176, 215]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0]),
              leftoverBitCount: 0,
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

            const result = Bitstring2.fromFloatSegment(segment);

            const expected = {
              type: "bitstring2",
              text: null,
              bytes: new Uint8Array([0, 0]),
              leftoverBitCount: 0,
            };

            assert.deepStrictEqual(result, expected);
          });
        });
      });
    });
  });

  it("fromText()", () => {
    const result = Bitstring2.fromText("Hologram");

    const expected = {
      type: "bitstring2",
      text: "Hologram",
      bytes: null,
      leftoverBitCount: 0,
    };

    assert.deepStrictEqual(result, expected);
  });

  describe("integerSegmentToBytes()", () => {
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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([10]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([10]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([10]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([10]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([170]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([170]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([170]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([170]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([10, 170]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([170, 10]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([10, 170]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([170, 10]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([107, 90]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([90, 107]);

                assert.deepStrictEqual(result, expected);
              });
            });

            describe("negative", () => {
              it("big-endian", () => {
                // 20 bits
                const segment = Type.bitstringSegment(Type.integer(-15897766), {
                  type: "integer",
                  size: Type.integer(8),
                  unit: 2n,
                  endianness: "big",
                });

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([107, 90]);

                assert.deepStrictEqual(result, expected);
              });

              it("little-endian", () => {
                // 20 bits
                const segment = Type.bitstringSegment(Type.integer(-15897766), {
                  type: "integer",
                  size: Type.integer(8),
                  unit: 2n,
                  endianness: "little",
                });

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([90, 107]);

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
                const segment = Type.bitstringSegment(Type.integer(225139414), {
                  type: "integer",
                  size: Type.integer(16),
                  unit: 2n,
                  endianness: "big",
                });

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([13, 107, 90, 214]);

                assert.deepStrictEqual(result, expected);
              });

              it("little-endian", () => {
                // 28 bits
                const segment = Type.bitstringSegment(Type.integer(225139414), {
                  type: "integer",
                  size: Type.integer(16),
                  unit: 2n,
                  endianness: "little",
                });

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([214, 90, 107, 13]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([13, 107, 90, 214]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([214, 90, 107, 13]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([107, 90, 214, 181]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([181, 214, 90, 107]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([107, 90, 214, 181]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([181, 214, 90, 107]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([13, 107, 90, 214, 181]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([181, 214, 90, 107, 13]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([13, 107, 90, 214, 181]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([181, 214, 90, 107, 13]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([107, 90, 214, 181, 173]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([173, 181, 214, 90, 107]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([107, 90, 214, 181, 173]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([173, 181, 214, 90, 107]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([32]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([32]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([32]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([32]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([160]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([160]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([160]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([160]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([42, 160]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([170, 32]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([42, 160]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([170, 32]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([170, 160]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([170, 160]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([170, 160]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([170, 160]);

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
                const segment = Type.bitstringSegment(Type.integer(47625645), {
                  type: "integer",
                  size: Type.integer(14),
                  unit: 2n,
                  endianness: "big",
                });

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([45, 107, 90, 208]);

                assert.deepStrictEqual(result, expected);
              });

              it("little-endian", () => {
                // 26 bits
                const segment = Type.bitstringSegment(Type.integer(47625645), {
                  type: "integer",
                  size: Type.integer(14),
                  unit: 2n,
                  endianness: "little",
                });

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([173, 181, 214, 32]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([45, 107, 90, 208]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([173, 181, 214, 32]);

                assert.deepStrictEqual(result, expected);
              });
            });
          });

          describe("outside 28 bits range", () => {
            describe("positive", () => {
              it("big-endian", () => {
                // 30 bits
                const segment = Type.bitstringSegment(Type.integer(900557658), {
                  type: "integer",
                  size: Type.integer(14),
                  unit: 2n,
                  endianness: "big",
                });

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([90, 214, 181, 160]);

                assert.deepStrictEqual(result, expected);
              });

              it("little-endian", () => {
                // 30 bits
                const segment = Type.bitstringSegment(Type.integer(900557658), {
                  type: "integer",
                  size: Type.integer(14),
                  unit: 2n,
                  endianness: "little",
                });

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([90, 107, 173, 80]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([90, 214, 181, 160]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([90, 107, 173, 80]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([45, 107, 90, 214, 181, 160]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([90, 107, 173, 181, 214, 32]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([45, 107, 90, 214, 181, 160]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([90, 107, 173, 181, 214, 32]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([214, 181, 173, 107, 90, 208]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([173, 181, 214, 90, 107, 208]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([214, 181, 173, 107, 90, 208]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([173, 181, 214, 90, 107, 208]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  13, 107, 90, 214, 181, 173, 107, 90,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  90, 107, 173, 181, 214, 90, 107, 13,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  13, 107, 90, 214, 181, 173, 107, 90,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  90, 107, 173, 181, 214, 90, 107, 13,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  107, 90, 214, 181, 173, 107, 90, 214,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  214, 90, 107, 173, 181, 214, 90, 107,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  107, 90, 214, 181, 173, 107, 90, 214,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  214, 90, 107, 173, 181, 214, 90, 107,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  13, 107, 90, 214, 181, 173, 107, 90, 214,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  214, 90, 107, 173, 181, 214, 90, 107, 13,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  13, 107, 90, 214, 181, 173, 107, 90, 214,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  214, 90, 107, 173, 181, 214, 90, 107, 13,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  107, 90, 214, 181, 173, 107, 90, 214, 181,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  181, 214, 90, 107, 173, 181, 214, 90, 107,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  107, 90, 214, 181, 173, 107, 90, 214, 181,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  181, 214, 90, 107, 173, 181, 214, 90, 107,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  53, 173, 107, 90, 214, 181, 173, 107, 80,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  181, 214, 90, 107, 173, 181, 214, 90, 48,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  53, 173, 107, 90, 214, 181, 173, 107, 80,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  181, 214, 90, 107, 173, 181, 214, 90, 48,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  90, 214, 181, 173, 107, 90, 214, 181, 160,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  90, 107, 173, 181, 214, 90, 107, 173, 80,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  90, 214, 181, 173, 107, 90, 214, 181, 160,
                ]);

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

                const result = Bitstring2.integerSegmentToBytes(segment);

                const expected = new Uint8Array([
                  90, 107, 173, 181, 214, 90, 107, 173, 80,
                ]);

                assert.deepStrictEqual(result, expected);
              });
            });
          });
        });
      });
    });
  });

  describe("isPrintableCodePoint()", () => {
    it("code point in range 0x20..0x7E", () => {
      assert.isTrue(Bitstring2.isPrintableCodePoint(40));
    });

    it("code point not in range 0x20..0x7E", () => {
      assert.isFalse(Bitstring2.isPrintableCodePoint(128));
    });

    it("code point in range 0xA0..0xD7FF", () => {
      assert.isTrue(Bitstring2.isPrintableCodePoint(170));
    });

    it("code point not in range 0xA0..0xD7FF", () => {
      assert.isFalse(Bitstring2.isPrintableCodePoint(55296));
    });

    it("code point in range 0xE000..0xFFFD", () => {
      assert.isTrue(Bitstring2.isPrintableCodePoint(58000));
    });

    it("code point not in range 0xE000..0xFFFD", () => {
      assert.isFalse(Bitstring2.isPrintableCodePoint(65534));
    });

    it("code point in range 0x10000..0x10FFFF", () => {
      assert.isTrue(Bitstring2.isPrintableCodePoint(66000));
    });

    it("code point not in range 0x10000..0x10FFFF", () => {
      assert.isFalse(Bitstring2.isPrintableCodePoint(1114112));
    });

    it("one of special printable chars", () => {
      assert.isTrue(Bitstring2.isPrintableCodePoint(10));
    });

    it("not one of special printable chars", () => {
      assert.isFalse(Bitstring2.isPrintableCodePoint(14));
    });
  });

  describe("isPrintableText()", () => {
    it("empty text", () => {
      assert.isTrue(Bitstring2.isPrintableText(Type.bitstring2("")));
    });

    it("ASCII text", () => {
      assert.isTrue(Bitstring2.isPrintableText(Type.bitstring2("abc")));
    });

    it("Unicode text (Chinese)", () => {
      assert.isTrue(Bitstring2.isPrintableText(Type.bitstring2("全息图")));
    });

    it("with non-printable character", () => {
      // \x01 is not printable
      assert.isFalse(Bitstring2.isPrintableText(Type.bitstring2("a\x01b")));
    });

    it("with invalid UTF-8 sequence", () => {
      const bitstring = Bitstring2.fromBytes([255, 255]);
      assert.isFalse(Bitstring2.isPrintableText(bitstring));
    });

    it("with leftover bits", () => {
      // prettier-ignore
      const bits = [
        0, 1, 1, 0, 0, 0, 0, 1, // "a"
        0, 1, 1, 0, 0, 0, 1, 0, // "b"
        1, 0, 1
      ]

      const bitstring = Bitstring2.fromBits(bits);

      assert.isFalse(Bitstring2.isPrintableText(bitstring));
    });

    it("sets the text field if the bytes sequence is representable as text", () => {
      // "abc"
      const bitstring = Bitstring2.fromBytes([97, 98, 99]);

      assert.isNull(bitstring.text);

      Bitstring2.isPrintableText(bitstring);
      assert.equal(bitstring.text, "abc");
    });
  });

  describe("maybeSetBytesFromText()", () => {
    it("sets bytes when bytes is null", () => {
      const bitstring = Type.bitstring2("abc");

      Bitstring2.maybeSetBytesFromText(bitstring);
      assert.deepStrictEqual(bitstring.bytes, new Uint8Array([97, 98, 99]));
    });

    it("does nothing when bytes is already set", () => {
      const bitstring = Type.bitstring2("abc");

      const existingBytes = new Uint8Array([1, 2, 3]);
      bitstring.bytes = existingBytes;

      Bitstring2.maybeSetBytesFromText(bitstring);
      assert.strictEqual(bitstring.bytes, existingBytes);
    });

    it("handles empty string", () => {
      const bitstring = Type.bitstring2("");

      Bitstring2.maybeSetBytesFromText(bitstring);
      assert.deepStrictEqual(bitstring.bytes, new Uint8Array([]));
    });

    it("handles Unicode characters", () => {
      const bitstring = Type.bitstring2("全息图");

      Bitstring2.maybeSetBytesFromText(bitstring);

      assert.deepStrictEqual(
        bitstring.bytes,
        new Uint8Array([229, 133, 168, 230, 129, 175, 229, 155, 190]),
      );
    });
  });

  describe("maybeSetTextFromBytes()", () => {
    it("does nothing when text is already set to a string", () => {
      const bitstring = Type.bitstring2("existing text");
      bitstring.bytes = new Uint8Array([97, 98, 99]); // "abc"

      Bitstring2.maybeSetTextFromBytes(bitstring);
      assert.equal(bitstring.text, "existing text");
    });

    it("does nothing when text is already set to false", () => {
      const bitstring = Bitstring2.fromBytes([97, 98, 99]); // "abc"
      bitstring.text = false;

      Bitstring2.maybeSetTextFromBytes(bitstring);
      assert.isFalse(bitstring.text);
    });

    it("sets text from valid UTF-8 bytes", () => {
      const bitstring = Bitstring2.fromBytes([97, 98, 99]); // "abc"

      Bitstring2.maybeSetTextFromBytes(bitstring);
      assert.equal(bitstring.text, "abc");
    });

    it("sets text to false for invalid UTF-8 bytes", () => {
      const bitstring = Bitstring2.fromBytes([255, 255]); // Invalid UTF-8 sequence

      Bitstring2.maybeSetTextFromBytes(bitstring);
      assert.isFalse(bitstring.text);
    });
  });

  describe("resolveSegmentSize()", () => {
    it("returns explicit size when size is specified", () => {
      const segment = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
        size: Type.integer(16),
      });

      assert.equal(Bitstring2.resolveSegmentSize(segment), 16);
    });

    it("calculates size for binary segment with text", () => {
      const segment = {
        type: "binary",
        text: "全息图", // 9 bytes
      };

      assert.equal(Bitstring2.resolveSegmentSize(segment), 9);
    });

    it("calculates size for binary segment with bytes", () => {
      const segment = {
        type: "binary",
        bytes: new Uint8Array([1, 2, 3, 4]),
      };

      assert.equal(Bitstring2.resolveSegmentSize(segment), 4);
    });

    it("returns 64 for float segments", () => {
      const segment = Type.bitstringSegment(Type.float(123.45), {
        type: "float",
      });

      assert.equal(Bitstring2.resolveSegmentSize(segment), 64);
    });

    it("returns 8 for integer segments", () => {
      const segment = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
      });

      assert.equal(Bitstring2.resolveSegmentSize(segment), 8);
    });

    it("throws error for invalid segment type", () => {
      const segment = {
        type: "invalid_type",
      };

      assert.throw(
        () => Bitstring2.resolveSegmentSize(segment),
        HologramInterpreterError,
        `This case shouldn't be possible, segment = {"type":"invalid_type"}`,
      );
    });
  });

  describe("resolveSegmentUnit()", () => {
    it("returns explicit unit when specified", () => {
      const segment = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
        unit: 16n,
      });

      assert.equal(Bitstring2.resolveSegmentUnit(segment), 16);
    });

    it("returns 8 for binary segments without unit", () => {
      const segment = Type.bitstringSegment(Type.bitstring2("abc"), {
        type: "binary",
      });

      assert.equal(Bitstring2.resolveSegmentUnit(segment), 8);
    });

    it("returns 1 for float segments without unit", () => {
      const segment = Type.bitstringSegment(Type.float(123.45), {
        type: "float",
      });

      assert.equal(Bitstring2.resolveSegmentUnit(segment), 1);
    });

    it("returns 1 for integer segments without unit", () => {
      const segment = Type.bitstringSegment(Type.integer(123), {
        type: "integer",
      });

      assert.equal(Bitstring2.resolveSegmentUnit(segment), 1);
    });

    it("throws error for invalid segment type", () => {
      const segment = {
        type: "invalid_type",
      };

      assert.throw(
        () => Bitstring2.resolveSegmentUnit(segment),
        HologramInterpreterError,
        `This case shouldn't be possible, segment = {"type":"invalid_type"}`,
      );
    });
  });

  describe("validateCodePoint()", () => {
    it("integer that is a valid code point", () => {
      // a = 97
      assert.isTrue(Bitstring2.validateCodePoint(97));
    });

    it("integer that is not a valid code point", () => {
      // Max Unicode code point value is 1,114,112
      assert.isFalse(Bitstring2.validateCodePoint(1114113));
    });

    it("bigint that is a valid code point", () => {
      // a = 97
      assert.isTrue(Bitstring2.validateCodePoint(97n));
    });

    it("bigint that is not a valid code point", () => {
      // Max Unicode code point value is 1,114,112
      assert.isFalse(Bitstring2.validateCodePoint(1114113n));
    });

    it("not an integer or a bigint", () => {
      assert.isFalse(Bitstring2.validateCodePoint("abc"));
    });
  });

  // TODO: implement consistency tests
  describe("validateSegment()", () => {
    describe("binary segments", () => {
      it("validates binary segment with byte-aligned bitstring value", () => {
        const segment = Type.bitstringSegment(Type.bitstring("abc"), {
          type: "binary",
        });

        assert.isTrue(Bitstring2.validateSegment(segment, 1));
      });

      it("rejects binary segment with non-byte-aligned bitstring value", () => {
        const segment = Type.bitstringSegment(
          {
            type: "bitstring2",
            bytes: new Uint8Array([255]),
            leftoverBitCount: 4,
          },
          {type: "binary"},
        );

        assertBoxedError(
          () => Bitstring2.validateSegment(segment, 1),
          "ArgumentError",
          "construction of binary failed: segment 1 of type 'binary': the size of the value <<15::size(4)>> is not a multiple of the unit for the segment",
        );
      });

      it("rejects binary segment with float value", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "binary",
        });

        assertBoxedError(
          () => Bitstring2.validateSegment(segment, 1),
          "ArgumentError",
          "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 123.45",
        );
      });

      it("rejects binary segment with integer value", () => {
        const segment = Type.bitstringSegment(Type.integer(123), {
          type: "binary",
        });

        assertBoxedError(
          () => Bitstring2.validateSegment(segment, 1),
          "ArgumentError",
          "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 123",
        );
      });
    });

    describe("bitstring segments", () => {
      it("validates bitstring segment with bitstring value", () => {
        const segment = Type.bitstringSegment(Type.bitstring("abc"), {
          type: "bitstring2",
        });

        assert.isTrue(Bitstring2.validateSegment(segment, 1));
      });

      it("rejects bitstring segment with float value", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "bitstring2",
        });

        assertBoxedError(
          () => Bitstring2.validateSegment(segment, 1),
          "ArgumentError",
          "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 123.45",
        );
      });

      it("rejects bitstring segment with integer value", () => {
        const segment = Type.bitstringSegment(Type.integer(123), {
          type: "bitstring2",
        });

        assertBoxedError(
          () => Bitstring2.validateSegment(segment, 1),
          "ArgumentError",
          "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 123",
        );
      });

      it("rejects bitstring segment with size specified", () => {
        const segment = Type.bitstringSegment(Type.bitstring("abc"), {
          type: "bitstring2",
          size: Type.integer(16),
        });

        assertBoxedError(
          () => Bitstring2.validateSegment(segment, 1),
          "ArgumentError",
          `construction of binary failed: segment 1 of type 'integer': expected an integer but got: "abc"`,
        );
      });

      it("rejects bitstring segment with signedness specified", () => {
        const segment = Type.bitstringSegment(Type.bitstring("abc"), {
          type: "bitstring2",
          signedness: "unsigned",
        });

        assertBoxedError(
          () => Bitstring2.validateSegment(segment, 1),
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

        assert.isTrue(Bitstring2.validateSegment(segment, 1));
      });

      it("validates float segment with integer value", () => {
        const segment = Type.bitstringSegment(Type.integer(123), {
          type: "float",
        });

        assert.isTrue(Bitstring2.validateSegment(segment, 1));
      });

      it("validates float segment with variable pattern value", () => {
        const segment = Type.bitstringSegment(Type.variablePattern("abc"), {
          type: "float",
        });

        assert.isTrue(Bitstring2.validateSegment(segment, 1));
      });

      it("rejects float segment with bitstring value", () => {
        const segment = Type.bitstringSegment(Type.bitstring("abc"), {
          type: "float",
        });

        assertBoxedError(
          () => Bitstring2.validateSegment(segment, 1),
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
          () => Bitstring2.validateSegment(segment, 1),
          "CompileError",
          "integer and float types require a size specifier if the unit specifier is given",
        );
      });

      it("validates float segment with valid bit size", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "float",
          size: Type.integer(32),
        });

        assert.isTrue(Bitstring2.validateSegment(segment, 1));
      });

      it("rejects float segment with invalid bit size", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "float",
          size: Type.integer(24),
        });

        assertBoxedError(
          () => Bitstring2.validateSegment(segment, 1),
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

        assert.isTrue(Bitstring2.validateSegment(segment, 1));
      });

      it("validates integer segment with variable pattern value", () => {
        const segment = Type.bitstringSegment(Type.variablePattern("abc"), {
          type: "integer",
        });

        assert.isTrue(Bitstring2.validateSegment(segment, 1));
      });

      it("rejects integer segment with float value", () => {
        const segment = Type.bitstringSegment(Type.float(123.45), {
          type: "integer",
        });

        assertBoxedError(
          () => Bitstring2.validateSegment(segment, 1),
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

          assert.isTrue(Bitstring2.validateSegment(segment, 1));
        });

        it("rejects utf8 segment with float value", () => {
          const segment = Type.bitstringSegment(Type.float(123.45), {
            type: "utf8",
          });

          assertBoxedError(
            () => Bitstring2.validateSegment(segment, 1),
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
            () => Bitstring2.validateSegment(segment, 1),
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
            () => Bitstring2.validateSegment(segment, 1),
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
            () => Bitstring2.validateSegment(segment, 1),
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

          assert.isTrue(Bitstring2.validateSegment(segment, 1));
        });

        it("rejects utf16 segment with float value", () => {
          const segment = Type.bitstringSegment(Type.float(123.45), {
            type: "utf16",
          });

          assertBoxedError(
            () => Bitstring2.validateSegment(segment, 1),
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
            () => Bitstring2.validateSegment(segment, 1),
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
            () => Bitstring2.validateSegment(segment, 1),
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
            () => Bitstring2.validateSegment(segment, 1),
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

          assert.isTrue(Bitstring2.validateSegment(segment, 1));
        });

        it("rejects utf32 segment with float value", () => {
          const segment = Type.bitstringSegment(Type.float(123.45), {
            type: "utf32",
          });

          assertBoxedError(
            () => Bitstring2.validateSegment(segment, 1),
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
            () => Bitstring2.validateSegment(segment, 1),
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
            () => Bitstring2.validateSegment(segment, 1),
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
            () => Bitstring2.validateSegment(segment, 1),
            "ArgumentError",
            "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 97",
          );
        });
      });
    });
  });
});
