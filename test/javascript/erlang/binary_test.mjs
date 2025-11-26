"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedStrictEqual,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang_Binary from "../../../assets/js/erlang/binary.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const atomAbc = Type.atom("abc");

const integer0 = Type.integer(0);
const integer1 = Type.integer(1);
const integer3 = Type.integer(3);

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

        assert(Type.isTuple(result));
        assert.strictEqual(result.data.length, 2);
        assert(Type.isAtom(result.data[0]));
        assert.strictEqual(result.data[0].value, "bm");
        assert.strictEqual(result.data[1].node.words, pattern);
      });

      it("handles empty binary pattern", () => {
        const pattern = Bitstring.fromBytes([]);
        const result = compilePattern(pattern);

        assert(Type.isTuple(result));
        assert.strictEqual(result.data[0].value, "bm");
        assert.strictEqual(result.data[1].node.words, pattern);
      });
    });

    describe("with list of binary patterns", () => {
      it("returns Aho-Corasick compiled pattern tuple", () => {
        const pattern1 = Bitstring.fromBytes([72, 101]); // "He"
        const pattern2 = Bitstring.fromBytes([108, 108]); // "ll"
        const patternList = Type.list([pattern1, pattern2]);
        const result = compilePattern(patternList);

        assert(Type.isTuple(result));
        assert.strictEqual(result.data.length, 2);
        assert(Type.isAtom(result.data[0]));
        assert.strictEqual(result.data[0].value, "ac");
        assert.deepStrictEqual(result.data[1].node.words, patternList);
      });

      it("handles single pattern in list", () => {
        const pattern = Bitstring.fromBytes([72, 101, 108, 108, 111]);
        const patternList = Type.list([pattern]);
        const result = compilePattern(patternList);

        assert(Type.isTuple(result));
        assert.strictEqual(result.data[0].value, "ac");
        assert.deepStrictEqual(result.data[1].node.words, patternList);
      });

      it("raises ArgumentError for list containing non-binary", () => {
        const validPattern = Bitstring.fromBytes([72, 101]);
        const invalidPattern = Type.atom("not_binary");
        const patternList = Type.list([validPattern, invalidPattern]);

        assertBoxedError(
          () => compilePattern(patternList),
          "ArgumentError",
          "is not a valid pattern",
        );
      });

      it("raises ArgumentError for list containing bitstring", () => {
        const validPattern = Bitstring.fromBytes([72, 101]);
        const bitstringPattern = Type.bitstring([1, 0, 1]); // 3 bits, not a binary
        const patternList = Type.list([validPattern, bitstringPattern]);

        assertBoxedError(
          () => compilePattern(patternList),
          "ArgumentError",
          "is not a valid pattern",
        );
      });
    });

    describe("with compiled pattern tuple", () => {
      it("recreates Boyer-Moore matcher from bm tuple", () => {
        const pattern = Bitstring.fromBytes([72, 101, 108, 108, 111]);
        const compiledPattern = compilePattern(pattern);
        const result = compilePattern(compiledPattern);

        assert(Type.isTuple(result));
        assert.strictEqual(result.data[0].value, "bm");
        assert.strictEqual(result.data[1].node.words, pattern);
      });

      it("recreates Aho-Corasick matcher from ac tuple", () => {
        const pattern1 = Bitstring.fromBytes([72, 101]); // "He"
        const pattern2 = Bitstring.fromBytes([108, 108]); // "ll"
        const patternList = Type.list([pattern1, pattern2]);
        const compiledPattern = compilePattern(patternList);
        const result = compilePattern(compiledPattern);

        assert(Type.isTuple(result));
        assert.strictEqual(result.data[0].value, "ac");
        assert.deepStrictEqual(result.data[1].node.words, patternList);
      });

      it("raises ArgumentError for unknown algorithm atom", () => {
        const unknownAlgoPattern = Type.tuple([
          Type.atom("unknown_algo"),
          {pattern: [72, 101]},
        ]);

        assertBoxedError(
          () => compilePattern(unknownAlgoPattern),
          "ArgumentError",
          "is not a valid pattern",
        );
      });
    });

    describe("with invalid pattern types", () => {
      it("raises ArgumentError for integer", () => {
        assertBoxedError(
          () => compilePattern(Type.integer(123)),
          "ArgumentError",
          "is not a valid pattern",
        );
      });

      it("raises ArgumentError for atom", () => {
        assertBoxedError(
          () => compilePattern(Type.atom("invalid")),
          "ArgumentError",
          "is not a valid pattern",
        );
      });

      it("raises ArgumentError for bitstring (non-binary)", () => {
        const bitstring = Type.bitstring([1, 0, 1]); // 3 bits

        assertBoxedError(
          () => compilePattern(bitstring),
          "ArgumentError",
          "is not a valid pattern",
        );
      });
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

  describe("_boyerMoorePatternMatcher", () => {
    it("computes bad shift table correctly", () => {
      const pattern = Bitstring.fromBytes([104, 101, 108, 108, 111]);
      const compiled = Erlang_Binary._boyerMoorePatternMatcher(pattern);

      assert.strictEqual(compiled.data[0].value, "bm");
      assert.strictEqual(compiled.data[1].node.algorithm, "boyer_moore");
      assert.strictEqual(compiled.data[1].node.words, pattern);
    });
  });

  describe("_ahoCorasickPatternMatcher", () => {
    it("builds trie structure for multiple patterns", () => {
      const pattern1 = Bitstring.fromBytes([104, 101]); // "he"
      const pattern2 = Bitstring.fromBytes([115, 104, 101]); // "she"
      const pattern3 = Bitstring.fromBytes([104, 105, 115]); // "his"
      const patternList = Type.list([pattern1, pattern2, pattern3]);
      const compiled = Erlang_Binary._ahoCorasickPatternMatcher(patternList);

      assert.strictEqual(compiled.data[0].value, "ac");
      assert.strictEqual(compiled.data[1].node.algorithm, "aho_corasick");
      assert.deepStrictEqual(compiled.data[1].node.words, patternList);
    });

    it("handles overlapping patterns", () => {
      const pattern1 = Bitstring.fromBytes([97, 98]); // "ab"
      const pattern2 = Bitstring.fromBytes([97, 98, 99]); // "abc"
      const patternList = Type.list([pattern1, pattern2]);
      const compiled = Erlang_Binary._ahoCorasickPatternMatcher(patternList);

      assert.strictEqual(compiled.data[0].value, "ac");
      assert.deepStrictEqual(compiled.data[1].node.words, patternList);
    });
  });
});
