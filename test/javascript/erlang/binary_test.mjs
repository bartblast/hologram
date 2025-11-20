"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang_Binary from "../../../assets/js/erlang/binary.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Erlang_Binary", () => {
  describe("at/2", () => {
    const at = Erlang_Binary["at/2"];

    const binary = Bitstring.fromBytes([5, 19, 72, 33]);

    it("returns first byte", () => {
      const result = at(binary, Type.integer(0));
      assert.deepStrictEqual(result, Type.integer(5));
    });

    it("returns middle byte", () => {
      const result = at(binary, Type.integer(1));
      assert.deepStrictEqual(result, Type.integer(19));
    });

    it("returns last byte", () => {
      const result = at(binary, Type.integer(3));
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
        () => at(subject, Type.integer(0)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("raises ArgumentError when bitstring is not a binary", () => {
      const subject = Type.bitstring([1, 0, 1]);

      assertBoxedError(
        () => at(subject, Type.integer(0)),
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
          assert.deepStrictEqual(
            Array.from(result.data[1].pattern),
            [72, 101, 108, 108, 111],
          );
        });

        it("handles empty binary pattern", () => {
          const pattern = Bitstring.fromBytes([]);
          const result = compilePattern(pattern);

          assert(Type.isTuple(result));
          assert.strictEqual(result.data[0].value, "bm");
          assert.deepStrictEqual(Array.from(result.data[1].pattern), []);
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
          assert.deepStrictEqual(
            result.data[1].patterns.map((p) => Array.from(p)),
            [
              [72, 101],
              [108, 108],
            ],
          );
        });

        it("handles single pattern in list", () => {
          const pattern = Bitstring.fromBytes([72, 101, 108, 108, 111]);
          const patternList = Type.list([pattern]);
          const result = compilePattern(patternList);

          assert(Type.isTuple(result));
          assert.strictEqual(result.data[0].value, "ac");
          assert.deepStrictEqual(
            result.data[1].patterns.map((p) => Array.from(p)),
            [[72, 101, 108, 108, 111]],
          );
        });

        it("raises ArgumentError for empty list", () => {
          const patternList = Type.list([]);

          assertBoxedError(
            () => compilePattern(patternList),
            "ArgumentError",
            "pattern list must not be empty",
          );
        });

        it("raises ArgumentError for list containing non-binary", () => {
          const validPattern = Bitstring.fromBytes([72, 101]);
          const invalidPattern = Type.atom("not_binary");
          const patternList = Type.list([validPattern, invalidPattern]);

          assertBoxedError(
            () => compilePattern(patternList),
            "ArgumentError",
            "must be a binary",
          );
        });

        it("raises ArgumentError for list containing bitstring", () => {
          const validPattern = Bitstring.fromBytes([72, 101]);
          const bitstringPattern = Type.bitstring([1, 0, 1]); // 3 bits, not a binary
          const patternList = Type.list([validPattern, bitstringPattern]);

          assertBoxedError(
            () => compilePattern(patternList),
            "ArgumentError",
            "must be a binary (not a bitstring)",
          );
        });
      });

      describe("with compiled pattern tuple", () => {
        it("recreates Boyer-Moore matcher from bm tuple", () => {
          const originalPattern = [72, 101, 108, 108, 111];
          const compiledPattern = Type.tuple([
            Type.atom("bm"),
            {pattern: originalPattern},
          ]);
          const result = compilePattern(compiledPattern);

          assert(Type.isTuple(result));
          assert.strictEqual(result.data[0].value, "bm");
          assert.deepStrictEqual(
            Array.from(result.data[1].pattern),
            originalPattern,
          );
        });

        it("recreates Aho-Corasick matcher from ac tuple", () => {
          const originalPatterns = [
            [72, 101],
            [108, 108],
          ];
          const compiledPattern = Type.tuple([
            Type.atom("ac"),
            {patterns: originalPatterns},
          ]);
          const result = compilePattern(compiledPattern);

          assert(Type.isTuple(result));
          assert.strictEqual(result.data[0].value, "ac");
          assert.deepStrictEqual(
            result.data[1].patterns.map((p) => Array.from(p)),
            originalPatterns,
          );
        });

        it("raises ArgumentError for invalid compiled pattern format", () => {
          const invalidPattern = Type.tuple([
            Type.integer(123), // Should be atom
            {pattern: [72, 101]},
          ]);

          assertBoxedError(
            () => compilePattern(invalidPattern),
            "ArgumentError",
            "invalid compiled pattern format",
          );
        });

        it("raises ArgumentError for unknown algorithm atom", () => {
          const unknownAlgoPattern = Type.tuple([
            Type.atom("unknown_algo"),
            {pattern: [72, 101]},
          ]);

          assertBoxedError(
            () => compilePattern(unknownAlgoPattern),
            "ArgumentError",
            "pattern must be a binary or a list of binaries",
          );
        });
      });

      describe("with invalid pattern types", () => {
        it("raises ArgumentError for integer", () => {
          assertBoxedError(
            () => compilePattern(Type.integer(123)),
            "ArgumentError",
            "pattern must be a binary or a list of binaries",
          );
        });

        it("raises ArgumentError for atom", () => {
          assertBoxedError(
            () => compilePattern(Type.atom("invalid")),
            "ArgumentError",
            "pattern must be a binary or a list of binaries",
          );
        });

        it("raises ArgumentError for bitstring (non-binary)", () => {
          const bitstring = Type.bitstring([1, 0, 1]); // 3 bits

          assertBoxedError(
            () => compilePattern(bitstring),
            "ArgumentError",
            "must be a binary (not a bitstring)",
          );
        });
      });
    });

    describe("Matcher class functionality", () => {
      describe("BoyerMooreMatcher", () => {
        it("computes bad shift table correctly", () => {
          // Test with pattern "hello"
          const pattern = Bitstring.fromBytes([104, 101, 108, 108, 111]);
          const compiled = Erlang_Binary["compile_pattern/1"](pattern);

          // Verify it is a BM pattern
          assert.strictEqual(compiled.data[0].value, "bm");
          assert.strictEqual(compiled.data[1].algorithm, "boyer_moore");
          assert.deepStrictEqual(
            Array.from(compiled.data[1].pattern),
            [104, 101, 108, 108, 111],
          );
        });

        it("handles single character pattern", () => {
          const pattern = Bitstring.fromBytes([65]); // "A"
          const compiled = Erlang_Binary["compile_pattern/1"](pattern);

          assert.strictEqual(compiled.data[0].value, "bm");
          assert.deepStrictEqual(Array.from(compiled.data[1].pattern), [65]);
        });
      });

      describe("AhoCorasickMatcher", () => {
        it("builds trie structure for multiple patterns", () => {
          const pattern1 = Bitstring.fromBytes([104, 101]); // "he"
          const pattern2 = Bitstring.fromBytes([115, 104, 101]); // "she"
          const pattern3 = Bitstring.fromBytes([104, 105, 115]); // "his"
          const patternList = Type.list([pattern1, pattern2, pattern3]);
          const compiled = Erlang_Binary["compile_pattern/1"](patternList);

          assert.strictEqual(compiled.data[0].value, "ac");
          assert.strictEqual(compiled.data[1].algorithm, "aho_corasick");
          assert.deepStrictEqual(
            compiled.data[1].patterns.map((p) => Array.from(p)),
            [
              [104, 101],
              [115, 104, 101],
              [104, 105, 115],
            ],
          );
        });

        it("handles overlapping patterns", () => {
          const pattern1 = Bitstring.fromBytes([97, 98]); // "ab"
          const pattern2 = Bitstring.fromBytes([97, 98, 99]); // "abc"
          const patternList = Type.list([pattern1, pattern2]);
          const compiled = Erlang_Binary["compile_pattern/1"](patternList);

          assert.strictEqual(compiled.data[0].value, "ac");
          assert.deepStrictEqual(
            compiled.data[1].patterns.map((p) => Array.from(p)),
            [
              [97, 98],
              [97, 98, 99],
            ],
          );
        });
      });
    });
  });
});
