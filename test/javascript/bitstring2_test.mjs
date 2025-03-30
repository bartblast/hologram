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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                    unit: Type.integer(2),
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
                    unit: Type.integer(2),
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
                    unit: Type.integer(2),
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
                    unit: Type.integer(2),
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
                    unit: Type.integer(2),
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
                    unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                    unit: Type.integer(2),
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
                    unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                  unit: Type.integer(2),
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
                    unit: Type.integer(2),
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
                    unit: Type.integer(2),
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
                    unit: Type.integer(2),
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
                    unit: Type.integer(2),
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
                const segment = Type.bitstringSegment(
                  Type.integer(-278353782412454),
                  {
                    type: "integer",
                    size: Type.integer(22),
                    unit: Type.integer(2),
                    endianness: "big",
                  },
                );

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([45, 107, 90, 214, 181, 160]);

                assert.deepStrictEqual(result, expected);
              });

              it("little-endian", () => {
                const segment = Type.bitstringSegment(
                  Type.integer(-278353782412454),
                  {
                    type: "integer",
                    size: Type.integer(22),
                    unit: Type.integer(2),
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
                const segment = Type.bitstringSegment(
                  Type.integer(49939108771245),
                  {
                    type: "integer",
                    size: Type.integer(22),
                    unit: Type.integer(2),
                    endianness: "big",
                  },
                );

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([214, 181, 173, 107, 90, 208]);

                assert.deepStrictEqual(result, expected);
              });

              it("little-endian", () => {
                const segment = Type.bitstringSegment(
                  Type.integer(49939108771245),
                  {
                    type: "integer",
                    size: Type.integer(22),
                    unit: Type.integer(2),
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
                  // 42 bits
                  Type.integer(-231535867939411),
                  {
                    type: "integer",
                    size: Type.integer(22),
                    unit: Type.integer(2),
                    endianness: "big",
                  },
                );

                const result = Bitstring2.integerSegmentToBytes(segment);
                const expected = new Uint8Array([214, 181, 173, 107, 90, 208]);

                assert.deepStrictEqual(result, expected);
              });

              it("little-endian", () => {
                const segment = Type.bitstringSegment(
                  // 42 bits
                  Type.integer(-231535867939411),
                  {
                    type: "integer",
                    size: Type.integer(22),
                    unit: Type.integer(2),
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

    describe("integers outside Number range", () => {});
  });
});
