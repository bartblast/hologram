"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Bitstring2 from "../../assets/js/bitstring2.mjs";
import HologramInterpreterError from "../../assets/js/errors/interpreter_error.mjs";
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

  describe("floatSegmentToBytes()", () => {
    describe("positive float value", () => {
      describe("64-bit", () => {
        it("big-endian", () => {
          const segment = Type.bitstringSegment(Type.float(123.45), {
            type: "float",
            size: Type.integer(32),
            unit: Type.integer(2),
            endianness: "big",
          });

          const result = Bitstring2.floatSegmentToBytes(segment);

          const expected = new Uint8Array([
            64, 94, 220, 204, 204, 204, 204, 205,
          ]);

          assert.deepStrictEqual(result, expected);
        });

        it("little-endian", () => {
          const segment = Type.bitstringSegment(Type.float(123.45), {
            type: "float",
            size: Type.integer(32),
            unit: Type.integer(2),
            endianness: "little",
          });

          const result = Bitstring2.floatSegmentToBytes(segment);

          const expected = new Uint8Array([
            205, 204, 204, 204, 204, 220, 94, 64,
          ]);

          assert.deepStrictEqual(result, expected);
        });
      });

      describe("32-bit", () => {
        it("big-endian", () => {
          const segment = Type.bitstringSegment(Type.float(123.45), {
            type: "float",
            size: Type.integer(16),
            unit: Type.integer(2),
            endianness: "big",
          });

          const result = Bitstring2.floatSegmentToBytes(segment);
          const expected = new Uint8Array([66, 246, 230, 102]);

          assert.deepStrictEqual(result, expected);
        });

        it("little-endian", () => {
          const segment = Type.bitstringSegment(Type.float(123.45), {
            type: "float",
            size: Type.integer(16),
            unit: Type.integer(2),
            endianness: "little",
          });

          const result = Bitstring2.floatSegmentToBytes(segment);
          const expected = new Uint8Array([102, 230, 246, 66]);

          assert.deepStrictEqual(result, expected);
        });
      });

      describe("16-bit", () => {
        it("big-endian", () => {
          const segment = Type.bitstringSegment(Type.float(123.45), {
            type: "float",
            size: Type.integer(8),
            unit: Type.integer(2),
            endianness: "big",
          });

          assert.throw(
            () => Bitstring2.floatSegmentToBytes(segment),
            HologramInterpreterError,
            "16-bit float bitstring segments are not yet implemented in Hologram",
          );
        });

        it("little-endian", () => {
          const segment = Type.bitstringSegment(Type.float(123.45), {
            type: "float",
            size: Type.integer(8),
            unit: Type.integer(2),
            endianness: "little",
          });

          assert.throw(
            () => Bitstring2.floatSegmentToBytes(segment),
            HologramInterpreterError,
            "16-bit float bitstring segments are not yet implemented in Hologram",
          );
        });
      });
    });

    describe("negative float value", () => {
      describe("64-bit", () => {
        it("big-endian", () => {
          const segment = Type.bitstringSegment(Type.float(-123.45), {
            type: "float",
            size: Type.integer(32),
            unit: Type.integer(2),
            endianness: "big",
          });

          const result = Bitstring2.floatSegmentToBytes(segment);

          const expected = new Uint8Array([
            192, 94, 220, 204, 204, 204, 204, 205,
          ]);

          assert.deepStrictEqual(result, expected);
        });

        it("little-endian", () => {
          const segment = Type.bitstringSegment(Type.float(-123.45), {
            type: "float",
            size: Type.integer(32),
            unit: Type.integer(2),
            endianness: "little",
          });

          const result = Bitstring2.floatSegmentToBytes(segment);

          const expected = new Uint8Array([
            205, 204, 204, 204, 204, 220, 94, 192,
          ]);

          assert.deepStrictEqual(result, expected);
        });
      });

      describe("32-bit", () => {
        it("big-endian", () => {
          const segment = Type.bitstringSegment(Type.float(-123.45), {
            type: "float",
            size: Type.integer(16),
            unit: Type.integer(2),
            endianness: "big",
          });

          const result = Bitstring2.floatSegmentToBytes(segment);
          const expected = new Uint8Array([194, 246, 230, 102]);

          assert.deepStrictEqual(result, expected);
        });

        it("little-endian", () => {
          const segment = Type.bitstringSegment(Type.float(-123.45), {
            type: "float",
            size: Type.integer(16),
            unit: Type.integer(2),
            endianness: "little",
          });

          const result = Bitstring2.floatSegmentToBytes(segment);
          const expected = new Uint8Array([102, 230, 246, 194]);

          assert.deepStrictEqual(result, expected);
        });
      });

      describe("16-bit", () => {
        it("big-endian", () => {
          const segment = Type.bitstringSegment(Type.float(-123.45), {
            type: "float",
            size: Type.integer(8),
            unit: Type.integer(2),
            endianness: "big",
          });

          assert.throw(
            () => Bitstring2.floatSegmentToBytes(segment),
            HologramInterpreterError,
            "16-bit float bitstring segments are not yet implemented in Hologram",
          );
        });

        it("little-endian", () => {
          const segment = Type.bitstringSegment(Type.float(-123.45), {
            type: "float",
            size: Type.integer(8),
            unit: Type.integer(2),
            endianness: "little",
          });

          assert.throw(
            () => Bitstring2.floatSegmentToBytes(segment),
            HologramInterpreterError,
            "16-bit float bitstring segments are not yet implemented in Hologram",
          );
        });
      });
    });

    describe("positive integer value", () => {
      describe("64-bit", () => {
        it("big-endian", () => {
          const segment = Type.bitstringSegment(Type.integer(123), {
            type: "float",
            size: Type.integer(32),
            unit: Type.integer(2),
            endianness: "big",
          });

          const result = Bitstring2.floatSegmentToBytes(segment);
          const expected = new Uint8Array([64, 94, 192, 0, 0, 0, 0, 0]);

          assert.deepStrictEqual(result, expected);
        });

        it("little-endian", () => {
          const segment = Type.bitstringSegment(Type.integer(123), {
            type: "float",
            size: Type.integer(32),
            unit: Type.integer(2),
            endianness: "little",
          });

          const result = Bitstring2.floatSegmentToBytes(segment);
          const expected = new Uint8Array([0, 0, 0, 0, 0, 192, 94, 64]);

          assert.deepStrictEqual(result, expected);
        });
      });

      describe("32-bit", () => {
        it("big-endian", () => {
          const segment = Type.bitstringSegment(Type.integer(123), {
            type: "float",
            size: Type.integer(16),
            unit: Type.integer(2),
            endianness: "big",
          });

          const result = Bitstring2.floatSegmentToBytes(segment);
          const expected = new Uint8Array([66, 246, 0, 0]);

          assert.deepStrictEqual(result, expected);
        });

        it("little-endian", () => {
          const segment = Type.bitstringSegment(Type.integer(123), {
            type: "float",
            size: Type.integer(16),
            unit: Type.integer(2),
            endianness: "little",
          });

          const result = Bitstring2.floatSegmentToBytes(segment);
          const expected = new Uint8Array([0, 0, 246, 66]);

          assert.deepStrictEqual(result, expected);
        });
      });

      describe("16-bit", () => {
        it("big-endian", () => {
          const segment = Type.bitstringSegment(Type.integer(123), {
            type: "float",
            size: Type.integer(8),
            unit: Type.integer(2),
            endianness: "big",
          });

          assert.throw(
            () => Bitstring2.floatSegmentToBytes(segment),
            HologramInterpreterError,
            "16-bit float bitstring segments are not yet implemented in Hologram",
          );
        });

        it("little-endian", () => {
          const segment = Type.bitstringSegment(Type.integer(123), {
            type: "float",
            size: Type.integer(8),
            unit: Type.integer(2),
            endianness: "little",
          });

          assert.throw(
            () => Bitstring2.floatSegmentToBytes(segment),
            HologramInterpreterError,
            "16-bit float bitstring segments are not yet implemented in Hologram",
          );
        });
      });
    });

    describe("negative integer value", () => {
      describe("64-bit", () => {
        it("big-endian", () => {
          const segment = Type.bitstringSegment(Type.integer(-123), {
            type: "float",
            size: Type.integer(32),
            unit: Type.integer(2),
            endianness: "big",
          });

          const result = Bitstring2.floatSegmentToBytes(segment);
          const expected = new Uint8Array([192, 94, 192, 0, 0, 0, 0, 0]);

          assert.deepStrictEqual(result, expected);
        });

        it("little-endian", () => {
          const segment = Type.bitstringSegment(Type.integer(-123), {
            type: "float",
            size: Type.integer(32),
            unit: Type.integer(2),
            endianness: "little",
          });

          const result = Bitstring2.floatSegmentToBytes(segment);
          const expected = new Uint8Array([0, 0, 0, 0, 0, 192, 94, 192]);

          assert.deepStrictEqual(result, expected);
        });
      });

      describe("32-bit", () => {
        it("big-endian", () => {
          const segment = Type.bitstringSegment(Type.integer(-123), {
            type: "float",
            size: Type.integer(16),
            unit: Type.integer(2),
            endianness: "big",
          });

          const result = Bitstring2.floatSegmentToBytes(segment);
          const expected = new Uint8Array([194, 246, 0, 0]);

          assert.deepStrictEqual(result, expected);
        });

        it("little-endian", () => {
          const segment = Type.bitstringSegment(Type.integer(-123), {
            type: "float",
            size: Type.integer(16),
            unit: Type.integer(2),
            endianness: "little",
          });

          const result = Bitstring2.floatSegmentToBytes(segment);
          const expected = new Uint8Array([0, 0, 246, 194]);

          assert.deepStrictEqual(result, expected);
        });
      });

      describe("16-bit", () => {
        it("big-endian", () => {
          const segment = Type.bitstringSegment(Type.integer(-123), {
            type: "float",
            size: Type.integer(8),
            unit: Type.integer(2),
            endianness: "big",
          });

          assert.throw(
            () => Bitstring2.floatSegmentToBytes(segment),
            HologramInterpreterError,
            "16-bit float bitstring segments are not yet implemented in Hologram",
          );
        });

        it("little-endian", () => {
          const segment = Type.bitstringSegment(Type.integer(-123), {
            type: "float",
            size: Type.integer(8),
            unit: Type.integer(2),
            endianness: "little",
          });

          assert.throw(
            () => Bitstring2.floatSegmentToBytes(segment),
            HologramInterpreterError,
            "16-bit float bitstring segments are not yet implemented in Hologram",
          );
        });
      });
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

  describe("integerSegmentToBytes()", () => {
    describe("value within Number range", () => {
      describe("positive", () => {
        describe("stored in 8 bits", () => {
          describe("within 8 bits range", () => {
            it("big-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(123), {
                type: "integer",
                size: Type.integer(4),
                unit: Type.integer(2),
                endianness: "big",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([123]);

              assert.deepStrictEqual(result, expected);
            });

            it("little-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(123), {
                type: "integer",
                size: Type.integer(4),
                unit: Type.integer(2),
                endianness: "little",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([123]);

              assert.deepStrictEqual(result, expected);
            });
          });

          describe("outside of 8 bits range", () => {
            it("big-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(1234), {
                type: "integer",
                size: Type.integer(4),
                unit: Type.integer(2),
                endianness: "big",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([210]);

              assert.deepStrictEqual(result, expected);
            });

            it("little-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(1234), {
                type: "integer",
                size: Type.integer(4),
                unit: Type.integer(2),
                endianness: "little",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([210]);

              assert.deepStrictEqual(result, expected);
            });
          });
        });

        describe("stored in 16 bits", () => {
          describe("within 16 bits range", () => {
            it("big-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(1234), {
                type: "integer",
                size: Type.integer(8),
                unit: Type.integer(2),
                endianness: "big",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([4, 210]);

              assert.deepStrictEqual(result, expected);
            });

            it("little-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(1234), {
                type: "integer",
                size: Type.integer(8),
                unit: Type.integer(2),
                endianness: "little",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([210, 4]);

              assert.deepStrictEqual(result, expected);
            });
          });

          describe("outside of 16 bits range", () => {
            it("big-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(123456), {
                type: "integer",
                size: Type.integer(8),
                unit: Type.integer(2),
                endianness: "big",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([226, 64]);

              assert.deepStrictEqual(result, expected);
            });

            it("little-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(123456), {
                type: "integer",
                size: Type.integer(8),
                unit: Type.integer(2),
                endianness: "little",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([64, 226]);

              assert.deepStrictEqual(result, expected);
            });
          });
        });

        describe("stored in 32 bits", () => {
          describe("within 32 bits range", () => {
            it("big-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(123456789), {
                type: "integer",
                size: Type.integer(16),
                unit: Type.integer(2),
                endianness: "big",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([7, 91, 205, 21]);

              assert.deepStrictEqual(result, expected);
            });

            it("little-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(123456789), {
                type: "integer",
                size: Type.integer(16),
                unit: Type.integer(2),
                endianness: "little",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([21, 205, 91, 7]);

              assert.deepStrictEqual(result, expected);
            });
          });

          describe("outside of 32 bits range", () => {
            it("big-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(12345678901), {
                type: "integer",
                size: Type.integer(16),
                unit: Type.integer(2),
                endianness: "big",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([223, 220, 28, 53]);

              assert.deepStrictEqual(result, expected);
            });

            it("little-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(12345678901), {
                type: "integer",
                size: Type.integer(16),
                unit: Type.integer(2),
                endianness: "little",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([53, 28, 220, 223]);

              assert.deepStrictEqual(result, expected);
            });
          });
        });

        describe("stored in 4 bits", () => {
          describe("within 4 bits range", () => {
            it("big-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(6), {
                type: "integer",
                size: Type.integer(2),
                unit: Type.integer(2),
                endianness: "big",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([96]);

              assert.deepStrictEqual(result, expected);
            });

            it("little-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(6), {
                type: "integer",
                size: Type.integer(2),
                unit: Type.integer(2),
                endianness: "little",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([96]);

              assert.deepStrictEqual(result, expected);
            });
          });

          describe("outside of 4 bits range", () => {
            it("big-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(54), {
                type: "integer",
                size: Type.integer(2),
                unit: Type.integer(2),
                endianness: "big",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([96]);

              assert.deepStrictEqual(result, expected);
            });

            it("little-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(54), {
                type: "integer",
                size: Type.integer(2),
                unit: Type.integer(2),
                endianness: "little",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([96]);

              assert.deepStrictEqual(result, expected);
            });
          });
        });

        describe("stored in 12 bits", () => {});

        describe("stored in 24 bits", () => {});

        describe("stored in more than 32 bits", () => {});
      });

      describe("negative", () => {
        describe("stored in 8 bits", () => {
          describe("within 8 bits range", () => {
            it("big-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(-123), {
                type: "integer",
                size: Type.integer(4),
                unit: Type.integer(2),
                endianness: "big",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([133]);

              assert.deepStrictEqual(result, expected);
            });

            it("little-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(-123), {
                type: "integer",
                size: Type.integer(4),
                unit: Type.integer(2),
                endianness: "little",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([133]);

              assert.deepStrictEqual(result, expected);
            });
          });

          describe("outside of 8 bits range", () => {
            it("big-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(-1234), {
                type: "integer",
                size: Type.integer(4),
                unit: Type.integer(2),
                endianness: "big",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([46]);

              assert.deepStrictEqual(result, expected);
            });

            it("little-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(-1234), {
                type: "integer",
                size: Type.integer(4),
                unit: Type.integer(2),
                endianness: "little",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([46]);

              assert.deepStrictEqual(result, expected);
            });
          });
        });

        describe("stored in 16 bits", () => {
          describe("within 16 bits range", () => {
            it("big-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(-1234), {
                type: "integer",
                size: Type.integer(8),
                unit: Type.integer(2),
                endianness: "big",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([251, 46]);

              assert.deepStrictEqual(result, expected);
            });

            it("little-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(-1234), {
                type: "integer",
                size: Type.integer(8),
                unit: Type.integer(2),
                endianness: "little",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([46, 251]);

              assert.deepStrictEqual(result, expected);
            });
          });

          describe("outside of 16 bits range", () => {
            it("big-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(-123456), {
                type: "integer",
                size: Type.integer(8),
                unit: Type.integer(2),
                endianness: "big",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([29, 192]);

              assert.deepStrictEqual(result, expected);
            });

            it("little-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(-123456), {
                type: "integer",
                size: Type.integer(8),
                unit: Type.integer(2),
                endianness: "little",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([192, 29]);

              assert.deepStrictEqual(result, expected);
            });
          });
        });

        describe("stored in 32 bits", () => {
          describe("within 32 bits range", () => {
            it("big-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(-123456789), {
                type: "integer",
                size: Type.integer(16),
                unit: Type.integer(2),
                endianness: "big",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([248, 164, 50, 235]);

              assert.deepStrictEqual(result, expected);
            });

            it("little-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(-123456789), {
                type: "integer",
                size: Type.integer(16),
                unit: Type.integer(2),
                endianness: "little",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([235, 50, 164, 248]);

              assert.deepStrictEqual(result, expected);
            });
          });

          describe("outside of 32 bits range", () => {
            it("big-endian", () => {
              const segment = Type.bitstringSegment(
                Type.integer(-12345678901),
                {
                  type: "integer",
                  size: Type.integer(16),
                  unit: Type.integer(2),
                  endianness: "big",
                },
              );

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([32, 35, 227, 203]);

              assert.deepStrictEqual(result, expected);
            });

            it("little-endian", () => {
              const segment = Type.bitstringSegment(
                Type.integer(-12345678901),
                {
                  type: "integer",
                  size: Type.integer(16),
                  unit: Type.integer(2),
                  endianness: "little",
                },
              );

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([203, 227, 35, 32]);

              assert.deepStrictEqual(result, expected);
            });
          });
        });

        describe("stored in 4 bits", () => {
          describe("within 4 bits range", () => {
            it("big-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(-250), {
                type: "integer",
                size: Type.integer(2),
                unit: Type.integer(2),
                endianness: "big",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([96]);

              assert.deepStrictEqual(result, expected);
            });

            it("little-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(-250), {
                type: "integer",
                size: Type.integer(2),
                unit: Type.integer(2),
                endianness: "little",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([96]);

              assert.deepStrictEqual(result, expected);
            });
          });

          describe("outside of 4 bits range", () => {
            it("big-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(-202), {
                type: "integer",
                size: Type.integer(2),
                unit: Type.integer(2),
                endianness: "big",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([96]);

              assert.deepStrictEqual(result, expected);
            });

            it("little-endian", () => {
              const segment = Type.bitstringSegment(Type.integer(-202), {
                type: "integer",
                size: Type.integer(2),
                unit: Type.integer(2),
                endianness: "little",
              });

              const result = Bitstring2.integerSegmentToBytes(segment);
              const expected = new Uint8Array([96]);

              assert.deepStrictEqual(result, expected);
            });
          });
        });

        describe("stored in 12 bits", () => {});

        describe("stored in 24 bits", () => {});

        describe("stored in more than 32 bits", () => {});
      });
    });

    describe("integers outside Number range", () => {});
  });
});
