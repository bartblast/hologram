"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedStrictEqual,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang_Binary from "../../../assets/js/erlang/binary.mjs";
import ERTS from "../../../assets/js/erts.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const atomAbc = Type.atom("abc");

const integer0 = Type.integer(0);
const integer1 = Type.integer(1);
const integer3 = Type.integer(3);
const integer123 = Type.integer(123);

const bytesBasedEmptyBinary = Bitstring.fromBytes([]);
const textBasedEmptyBinary = Bitstring.fromText("");

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/ex_js_consistency/erlang/binary_test.exs
// Always update both together.

describe("Erlang_Binary", () => {
  describe("at/2", () => {
    const at = Erlang_Binary["at/2"];

    const binary = Bitstring.fromBytes([5, 19, 72, 33]);

    it("returns first byte", () => {
      const result = at(binary, integer0);
      assert.deepStrictEqual(result, Type.integer(5));
    });

    it("returns middle byte", () => {
      const result = at(binary, integer1);
      assert.deepStrictEqual(result, Type.integer(19));
    });

    it("returns last byte", () => {
      const result = at(binary, integer3);
      assert.deepStrictEqual(result, Type.integer(33));
    });

    it("raises ArgumentError when position is out of range", () => {
      const pos = Type.integer(4);

      assertBoxedError(
        () => at(binary, pos),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError when subject is nil", () => {
      const subject = Type.nil();

      assertBoxedError(
        () => at(subject, integer0),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("raises ArgumentError when bitstring is not a binary", () => {
      const subject = Type.bitstring([1, 0, 1]);

      assertBoxedError(
        () => at(subject, integer0),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "is a bitstring (expected a binary)",
        ),
      );
    });

    it("raises ArgumentError when position is nil", () => {
      const pos = Type.nil();

      assertBoxedError(
        () => at(binary, pos),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });

    it("raises ArgumentError when position is negative", () => {
      const pos = Type.integer(-1);

      assertBoxedError(
        () => at(binary, pos),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });
  });

  describe("compile_pattern/1", () => {
    const compilePattern = Erlang_Binary["compile_pattern/1"];

    describe("with single binary pattern", () => {
      it("returns Boyer-Moore compiled pattern tuple", () => {
        const pattern = Bitstring.fromBytes([72, 101, 108, 108, 111]); // "Hello"
        const result = compilePattern(pattern);

        assert(Type.isCompiledPattern(result));
        assert.strictEqual(result.data[0].value, "bm");
      });

      it("stores the pattern in the binaryPattern registry", () => {
        const pattern = Bitstring.fromBytes([72, 101, 108, 108, 111]); // "Hello"
        const result = compilePattern(pattern);
        const ref = result.data[1];
        const words = ERTS.binaryPatternRegistry.get(ref);

        assert.strictEqual(words, pattern);
      });
    });

    describe("with list of binary patterns", () => {
      const pattern1 = Bitstring.fromBytes([72, 101]); // "He"
      const pattern2 = Bitstring.fromBytes([108, 108, 111]); // "llo"
      const patternList = Type.list([pattern1, pattern2]);

      it("returns Aho-Corasick compiled pattern tuple", () => {
        const result = compilePattern(patternList);

        assert(Type.isCompiledPattern(result));
        assert.strictEqual(result.data[0].value, "ac");
      });

      it("stores the pattern in the binaryPattern registry", () => {
        const result = compilePattern(patternList);
        const ref = result.data[1];
        const words = ERTS.binaryPatternRegistry.get(ref);

        assert.strictEqual(words, patternList);
      });

      it("accepts a list with only one element", () => {
        const oneItemList = Type.list([pattern1]);
        const result = compilePattern(oneItemList);
        assert(Type.isCompiledPattern(result));
      });
    });

    describe("Raises for invalid pattern types", () => {
      const invalidPatternTypes = {
        "nonbinary bitstring": Type.bitstring([1, 0, 1]),
        "empty binary": Bitstring.fromText(""),
        "empty list": Type.list([]),
        integer: Type.integer(1),
        atom: Type.atom("hello"),
        tuple: Type.tuple(["ab", "cd"]),
      };

      for (const name in invalidPatternTypes) {
        it(`raises ArgumentError when pattern is ${name}`, () => {
          assertBoxedError(
            () => compilePattern(invalidPatternTypes[name]),
            "ArgumentError",
            "is not a valid pattern",
          );
        });

        it(`raises ArgumentError when pattern is a list containing ${name}`, () => {
          const patternList = [
            Bitstring.fromText("Hello"),
            invalidPatternTypes[name],
          ];
          assertBoxedError(
            () => compilePattern(patternList),
            "ArgumentError",
            "is not a valid pattern",
          );
        });
      }
    });
  });

  describe("copy/2", () => {
    const testedFun = Erlang_Binary["copy/2"];

    describe("text-based", () => {
      describe("empty binary", () => {
        it("zero times", () => {
          const result = testedFun(textBasedEmptyBinary, integer0);

          assertBoxedStrictEqual(result, textBasedEmptyBinary);
        });

        it("one time", () => {
          const result = testedFun(textBasedEmptyBinary, integer1);

          assertBoxedStrictEqual(result, textBasedEmptyBinary);
        });

        it("multiple times", () => {
          const result = testedFun(textBasedEmptyBinary, integer3);

          assertBoxedStrictEqual(result, textBasedEmptyBinary);
        });
      });

      describe("non-empty binary", () => {
        const subject = Bitstring.fromText("hello");

        it("zero times", () => {
          const result = testedFun(subject, integer0);

          assertBoxedStrictEqual(result, textBasedEmptyBinary);
        });

        it("one time", () => {
          const result = testedFun(subject, integer1);

          assertBoxedStrictEqual(result, subject);
        });

        it("multiple times", () => {
          const result = testedFun(subject, integer3);
          const expected = Bitstring.fromText("hellohellohello");

          assertBoxedStrictEqual(result, expected);
        });
      });
    });

    describe("bytes-based", () => {
      describe("empty binary", () => {
        it("zero times", () => {
          const result = testedFun(bytesBasedEmptyBinary, integer0);

          assertBoxedStrictEqual(result, textBasedEmptyBinary);
        });

        it("one time", () => {
          const result = testedFun(bytesBasedEmptyBinary, integer1);

          assertBoxedStrictEqual(result, textBasedEmptyBinary);
        });

        it("multiple times", () => {
          const result = testedFun(bytesBasedEmptyBinary, integer3);

          assertBoxedStrictEqual(result, textBasedEmptyBinary);
        });
      });

      describe("non-empty binary", () => {
        const subject = Bitstring.fromBytes([65, 66, 67]);

        it("zero times", () => {
          const result = testedFun(subject, integer0);

          assertBoxedStrictEqual(result, textBasedEmptyBinary);
        });

        it("one time", () => {
          const result = testedFun(subject, integer1);

          assertBoxedStrictEqual(result, subject);
        });

        it("multiple times", () => {
          const result = testedFun(subject, integer3);

          const expected = Bitstring.fromBytes([
            65, 66, 67, 65, 66, 67, 65, 66, 67,
          ]);

          assertBoxedStrictEqual(result, expected);
        });
      });
    });

    describe("invalid arguments", () => {
      const subject = Type.bitstring("hello");

      it("raises ArgumentError if the first argument is not a bitstring", () => {
        assertBoxedError(
          () => testedFun(atomAbc, integer3),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a binary"),
        );
      });

      it("raises ArgumentError if the first argument is a non-binary bitstring", () => {
        assertBoxedError(
          () => testedFun(Type.bitstring([1, 0, 1]), integer3),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(
            1,
            "is a bitstring (expected a binary)",
          ),
        );
      });

      it("raises ArgumentError if the second argument is not an integer", () => {
        assertBoxedError(
          () => testedFun(subject, atomAbc),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not an integer"),
        );
      });

      it("raises ArgumentError if count is negative", () => {
        const count = Type.integer(-1);

        assertBoxedError(
          () => testedFun(subject, count),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "out of range"),
        );
      });
    });
  });

  describe("first/1", () => {
    const first = Erlang_Binary["first/1"];

    it("returns first byte of a single-byte binary", () => {
      const subject = Bitstring.fromBytes([42]);
      const result = first(subject);

      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("returns first byte of a multi-byte binary", () => {
      const subject = Bitstring.fromBytes([5, 4, 3]);
      const result = first(subject);

      assert.deepStrictEqual(result, Type.integer(5));
    });

    it("returns first byte of a text-based binary", () => {
      const subject = Bitstring.fromText("ELIXIR");
      const result = first(subject);

      assert.deepStrictEqual(result, Type.integer(69));
    });

    it("returns first byte of UTF-8 multi-byte character", () => {
      const subject = Bitstring.fromText("é");
      const result = first(subject);

      assert.deepStrictEqual(result, Type.integer(195));
    });

    it("raises ArgumentError if subject is not a bitstring", () => {
      assertBoxedError(
        () => first(integer123),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("raises ArgumentError if subject is a non-binary bitstring", () => {
      assertBoxedError(
        () => first(Type.bitstring([1, 0, 1])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "is a bitstring (expected a binary)",
        ),
      );
    });

    it("raises ArgumentError if subject is an empty binary", () => {
      assertBoxedError(
        () => first(Type.bitstring([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "a zero-sized binary is not allowed",
        ),
      );
    });
  });

  describe("_boyer_moore_pattern_matcher", () => {
    it("computes bad shift table correctly", () => {
      const pattern = Bitstring.fromBytes([104, 101, 108, 108, 111]);
      const result = Erlang_Binary._boyer_moore_pattern_matcher(pattern);
      assert(Type.isCompiledPattern(result));
    });
  });

  describe("_aho_corasick_pattern_matcher", () => {
    it("builds trie structure for multiple patterns", () => {
      const pattern1 = Bitstring.fromBytes([104, 101]); // "he"
      const pattern2 = Bitstring.fromBytes([115, 104, 101]); // "she"
      const patternList = Type.list([pattern1, pattern2]);
      const result = Erlang_Binary._aho_corasick_pattern_matcher(patternList);
      assert(Type.isCompiledPattern(result));
    });
  });
});
