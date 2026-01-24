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

const bytesBasedBinary = Bitstring.fromBytes([5, 19, 72, 33]);
const bytesBasedEmptyBinary = Bitstring.fromBytes([]);
const textBasedEmptyBinary = Bitstring.fromText("");

// TODO: consider
// const emptyList = Type.list([]);

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/ex_js_consistency/erlang/binary_test.exs
// Always update both together.

describe("Erlang_Binary", () => {
  describe("at/2", () => {
    const at = Erlang_Binary["at/2"];

    it("returns first byte", () => {
      const result = at(bytesBasedBinary, integer0);
      assert.deepStrictEqual(result, Type.integer(5));
    });

    it("returns middle byte", () => {
      const result = at(bytesBasedBinary, integer1);
      assert.deepStrictEqual(result, Type.integer(19));
    });

    it("returns last byte", () => {
      const result = at(bytesBasedBinary, integer3);
      assert.deepStrictEqual(result, Type.integer(33));
    });

    it("raises ArgumentError when position is out of range", () => {
      const pos = Type.integer(4);

      assertBoxedError(
        () => at(bytesBasedBinary, pos),
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
        () => at(bytesBasedBinary, pos),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });

    it("raises ArgumentError when position is negative", () => {
      const pos = Type.integer(-1);

      assertBoxedError(
        () => at(bytesBasedBinary, pos),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });
  });

  describe("compile_pattern/1", () => {
    const compilePattern = Erlang_Binary["compile_pattern/1"];

    const patternHello = Type.bitstring("Hello"); // [72, 101, 108, 108, 111]
    const patternHe = Type.bitstring("He"); // [72, 101]
    const patternLlo = Type.bitstring("llo"); // [108, 108, 111]

    describe("with valid input", () => {
      it("single binary pattern returns Boyer-Moore compiled pattern tuple", () => {
        const result = compilePattern(patternHello);

        assert.isTrue(Type.isCompiledPattern(result));
        assert.equal(result.data[0].value, "bm");
      });

      it("list of binary patterns returns Aho-Corasick compiled pattern tuple", () => {
        const patternList = Type.list([patternHe, patternLlo]);
        const result = compilePattern(patternList);

        assert.isTrue(Type.isCompiledPattern(result));
        assert.equal(result.data[0].value, "ac");
      });

      it("list with single element returns Boyer-Moore compiled pattern tuple", () => {
        const oneItemList = Type.list([patternHello]);
        const result = compilePattern(oneItemList);

        assert.isTrue(Type.isCompiledPattern(result));
        assert.equal(result.data[0].value, "bm");
      });
    });

    describe("errors with direct pattern", () => {
      it("raises ArgumentError when pattern is not bitstring", () => {
        assertBoxedError(
          () => compilePattern(Type.integer(1)),
          "ArgumentError",
          "is not a valid pattern",
        );
      });

      it("raises ArgumentError when pattern is non-binary bitstring", () => {
        assertBoxedError(
          () => compilePattern(Type.bitstring([1, 0, 1])),
          "ArgumentError",
          "is not a valid pattern",
        );
      });

      it("raises ArgumentError when pattern is empty binary", () => {
        assertBoxedError(
          () => compilePattern(Type.bitstring("")),
          "ArgumentError",
          "is not a valid pattern",
        );
      });

      it("raises ArgumentError when pattern is empty list", () => {
        assertBoxedError(
          () => compilePattern(Type.list()),
          "ArgumentError",
          "is not a valid pattern",
        );
      });
    });

    describe("errors with list containing invalid item", () => {
      it("raises ArgumentError when pattern is list containing non-bitstring", () => {
        assertBoxedError(
          () => compilePattern(Type.list([patternHello, Type.integer(1)])),
          "ArgumentError",
          "is not a valid pattern",
        );
      });

      it("raises ArgumentError when pattern is list containing non-binary bitstring", () => {
        assertBoxedError(
          () =>
            compilePattern(
              Type.list([patternHello, Type.bitstring([1, 0, 1])]),
            ),
          "ArgumentError",
          "is not a valid pattern",
        );
      });

      it("raises ArgumentError when pattern is list containing empty binary", () => {
        assertBoxedError(
          () => compilePattern(Type.list([patternHello, Type.bitstring("")])),
          "ArgumentError",
          "is not a valid pattern",
        );
      });

      it("raises ArgumentError when pattern is list containing empty list", () => {
        assertBoxedError(
          () => compilePattern(Type.list([patternHello, Type.list()])),
          "ArgumentError",
          "is not a valid pattern",
        );
      });
    });

    describe("client-only behaviour", () => {
      it("stores badShift in binaryPatternRegistry for BM pattern", () => {
        const result = compilePattern(patternHello);
        const ref = result.data[1];
        const saved = ERTS.binaryPatternRegistry.get(ref);

        // Spot check: 'G' (71) not in pattern, 'H' (72) is at index 0 of 5-char pattern
        assert.equal(saved.badShift["71"], -1);
        assert.equal(saved.badShift["72"], 4);
      });

      it("stores rootNode in binaryPatternRegistry for AC pattern", () => {
        const patternList = Type.list([patternHe, patternLlo]);
        const result = compilePattern(patternList);
        const ref = result.data[1];
        const saved = ERTS.binaryPatternRegistry.get(ref);

        // Root has children for 'H' (72) and 'l' (108)
        assert.deepEqual(Array.from(saved.rootNode.children.keys()), [72, 108]);
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

  describe("last/1", () => {
    const testedFun = Erlang_Binary["last/1"];

    it("returns last byte of a single-byte binary", () => {
      const subject = Bitstring.fromBytes([42]);
      const result = testedFun(subject);

      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("returns last byte of a multi-byte binary", () => {
      const result = testedFun(bytesBasedBinary);

      assert.deepStrictEqual(result, Type.integer(33));
    });

    it("returns last byte of a text-based binary", () => {
      const subject = Bitstring.fromText("ELIXIR");
      const result = testedFun(subject);

      assert.deepStrictEqual(result, Type.integer(82));
    });

    it("returns last byte of UTF-8 multi-byte character", () => {
      const subject = Bitstring.fromText("é");
      const result = testedFun(subject);

      assert.deepStrictEqual(result, Type.integer(169));
    });

    it("raises ArgumentError if subject is not a bitstring", () => {
      assertBoxedError(
        () => testedFun(atomAbc),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("raises ArgumentError if subject is a non-binary bitstring", () => {
      assertBoxedError(
        () => testedFun(Type.bitstring([1, 0, 1])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "is a bitstring (expected a binary)",
        ),
      );
    });

    it("raises ArgumentError if subject is an empty binary", () => {
      assertBoxedError(
        () => testedFun(textBasedEmptyBinary),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "a zero-sized binary is not allowed",
        ),
      );
    });
  });

  describe("split/2", () => {
    const split = Erlang_Binary["split/2"];

    it("splits on single pattern once", () => {
      const subject = Bitstring.fromText("hello world");
      const pattern = Bitstring.fromText(" ");
      const result = split(subject, pattern);

      assert.deepStrictEqual(
        result,
        Type.list([Bitstring.fromText("hello"), Bitstring.fromText("world")]),
      );
    });

    it("splits on single pattern when multiple matches exist", () => {
      const subject = Bitstring.fromText("hello world world");
      const pattern = Bitstring.fromText(" ");
      const result = split(subject, pattern);

      assert.deepStrictEqual(
        result,
        Type.list([
          Bitstring.fromText("hello"),
          Bitstring.fromText("world world"),
        ]),
      );
    });

    it("splits with multi-byte pattern", () => {
      const subject = Bitstring.fromText("aaabbbccc");
      const pattern = Bitstring.fromText("bb");
      const result = split(subject, pattern);

      assert.deepStrictEqual(
        result,
        Type.list([Bitstring.fromText("aaa"), Bitstring.fromText("bccc")]),
      );
    });

    it("returns list with original binary when pattern not found", () => {
      const subject = Bitstring.fromText("test");
      const pattern = Bitstring.fromText("x");
      const result = split(subject, pattern);

      assert.deepStrictEqual(result, Type.list([Bitstring.fromText("test")]));
    });

    it("splits with multiple patterns", () => {
      const subject = Bitstring.fromText("hello-world_test");
      const pattern = Type.list([
        Bitstring.fromText("-"),
        Bitstring.fromText("_"),
      ]);
      const result = split(subject, pattern);

      assert.deepStrictEqual(
        result,
        Type.list([
          Bitstring.fromText("hello"),
          Bitstring.fromText("world_test"),
        ]),
      );
    });

    it("handles empty subject", () => {
      const subject = Bitstring.fromText("");
      const pattern = Bitstring.fromText("x");
      const result = split(subject, pattern);

      assert.deepStrictEqual(result, Type.list([Bitstring.fromText("")]));
    });
  });

  describe("split/3", () => {
    const split = Erlang_Binary["split/3"];

    describe("with :global option", () => {
      it("splits on all occurrences", () => {
        const subject = Bitstring.fromText("hello world world");
        const pattern = Bitstring.fromText(" ");
        const options = Type.list([Type.atom("global")]);
        const result = split(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([
            Bitstring.fromText("hello"),
            Bitstring.fromText("world"),
            Bitstring.fromText("world"),
          ]),
        );
      });

      it("splits with multiple patterns globally", () => {
        const subject = Bitstring.fromText("hello-world_test");
        const pattern = Type.list([
          Bitstring.fromText("-"),
          Bitstring.fromText("_"),
        ]);
        const options = Type.list([Type.atom("global")]);
        const result = split(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([
            Bitstring.fromText("hello"),
            Bitstring.fromText("world"),
            Bitstring.fromText("test"),
          ]),
        );
      });

      it("handles consecutive patterns", () => {
        const subject = Bitstring.fromText("a--b--c");
        const pattern = Bitstring.fromText("-");
        const options = Type.list([Type.atom("global")]);
        const result = split(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([
            Bitstring.fromText("a"),
            Bitstring.fromText(""),
            Bitstring.fromText("b"),
            Bitstring.fromText(""),
            Bitstring.fromText("c"),
          ]),
        );
      });

      it("handles pattern at start, middle, and end", () => {
        const subject = Bitstring.fromText("-a-");
        const pattern = Bitstring.fromText("-");
        const options = Type.list([Type.atom("global")]);
        const result = split(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([
            Bitstring.fromText(""),
            Bitstring.fromText("a"),
            Bitstring.fromText(""),
          ]),
        );
      });

      it("handles invalid UTF-8 sequences in result", () => {
        // Create binary with invalid UTF-8: [65, 255, 66] where 255 is invalid
        const subject = Bitstring.fromBytes(
          new Uint8Array([65, 32, 255, 32, 66]),
        );
        const pattern = Bitstring.fromText(" ");
        const options = Type.list([Type.atom("global")]);
        const result = split(subject, pattern, options);

        // First part: [65] - valid UTF-8 "A"
        const firstPart = result.data[0];
        assert.strictEqual(firstPart.type, "bitstring");
        assert.strictEqual(firstPart.text, "A");

        // Second part: [255] - invalid UTF-8, should be bytes-based
        const secondPart = result.data[1];
        assert.strictEqual(secondPart.type, "bitstring");
        assert.strictEqual(secondPart.text, null);
        assert.deepStrictEqual(Array.from(secondPart.bytes), [255]);

        // Third part: [66] - valid UTF-8 "B"
        const thirdPart = result.data[2];
        assert.strictEqual(thirdPart.type, "bitstring");
        assert.strictEqual(thirdPart.text, "B");
      });
    });

    describe("without :global option", () => {
      it("splits only on first occurrence", () => {
        const subject = Bitstring.fromText("hello-world-test");
        const pattern = Bitstring.fromText("-");
        const options = Type.list([]);
        const result = split(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([
            Bitstring.fromText("hello"),
            Bitstring.fromText("world-test"),
          ]),
        );
      });
    });

    describe("compiled pattern behavior", () => {
      beforeEach(() => {
        ERTS.binaryPatternRegistry.patterns.clear();
      });

      it("splits using compiled Boyer-Moore pattern bytes", () => {
        const subject = Bitstring.fromText("hello world");
        const pattern = Bitstring.fromText("world");
        const compiledPattern = Erlang_Binary["compile_pattern/1"](pattern);
        const options = Type.list([]);

        const result = split(subject, compiledPattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([Bitstring.fromText("hello "), Bitstring.fromText("")]),
        );
      });

      it("raises ArgumentError when compiled pattern data is missing", () => {
        const subject = Bitstring.fromText("hello");
        const pattern = Bitstring.fromText("ell");
        const compiledPattern = Erlang_Binary["compile_pattern/1"](pattern);
        const patternRef = compiledPattern.data[1];
        const patternKey = Type.encodeMapKey(patternRef);
        ERTS.binaryPatternRegistry.patterns.delete(patternKey);

        const options = Type.list([]);

        assertBoxedError(
          () => split(subject, compiledPattern, options),
          "ArgumentError",
          "is not a valid pattern",
        );
      });
    });

    describe("options", () => {
      it("applies :trim to leading and trailing empties only", () => {
        const subject = Bitstring.fromText("-a-");
        const pattern = Bitstring.fromText("-");
        const options = Type.list([Type.atom("global"), Type.atom("trim")]);

        const result = split(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([Bitstring.fromText(""), Bitstring.fromText("a")]),
        );
      });

      it("applies :trim_all to remove all empty parts", () => {
        const subject = Bitstring.fromText("-a-");
        const pattern = Bitstring.fromText("-");
        const options = Type.list([Type.atom("global"), Type.atom("trim_all")]);

        const result = split(subject, pattern, options);

        assert.deepStrictEqual(result, Type.list([Bitstring.fromText("a")]));
      });

      it("respects scope option when a match exists in the range", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("b");
        const scope = Type.tuple([
          Type.atom("scope"),
          Type.tuple([Type.integer(1), Type.integer(1)]),
        ]);
        const options = Type.list([scope]);

        const result = split(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([Bitstring.fromText("a"), Bitstring.fromText("c")]),
        );
      });

      it("returns original binary when scope excludes the pattern", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("b");
        const scope = Type.tuple([
          Type.atom("scope"),
          Type.tuple([Type.integer(0), Type.integer(1)]),
        ]);
        const options = Type.list([scope]);

        const result = split(subject, pattern, options);

        assert.deepStrictEqual(result, Type.list([Bitstring.fromText("abc")]));
      });

      it("raises ArgumentError for negative scope start", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("b");
        const scope = Type.tuple([
          Type.atom("scope"),
          Type.tuple([Type.integer(-1), Type.integer(2)]),
        ]);
        const options = Type.list([scope]);

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          "invalid options",
        );
      });

      it("scope with zero length returns original binary", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("b");
        const scope = Type.tuple([
          Type.atom("scope"),
          Type.tuple([Type.integer(1), Type.integer(0)]),
        ]);
        const options = Type.list([scope]);

        const result = split(subject, pattern, options);

        assert.deepStrictEqual(result, Type.list([Bitstring.fromText("abc")]));
      });

      it("scope extending beyond subject length raises ArgumentError", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("b");
        const scope = Type.tuple([
          Type.atom("scope"),
          Type.tuple([Type.integer(1), Type.integer(3)]),
        ]);
        const options = Type.list([scope]);

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          "invalid options",
        );
      });

      it("scope with multiple patterns (Aho-Corasick)", () => {
        const subject = Bitstring.fromText("hello-world");
        const pattern = Type.list([
          Bitstring.fromText("-"),
          Bitstring.fromText("o"),
        ]);
        const scope = Type.tuple([
          Type.atom("scope"),
          Type.tuple([Type.integer(0), Type.integer(11)]),
        ]);
        const options = Type.list([scope, Type.atom("global")]);

        const result = split(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([
            Bitstring.fromText("hell"),
            Bitstring.fromText(""),
            Bitstring.fromText("w"),
            Bitstring.fromText("rld"),
          ]),
        );
      });

      it("scope with trim removes trailing empties within scope", () => {
        const subject = Bitstring.fromText("a-b--");
        const pattern = Bitstring.fromText("-");
        const scope = Type.tuple([
          Type.atom("scope"),
          Type.tuple([Type.integer(0), Type.integer(5)]),
        ]);
        const options = Type.list([
          scope,
          Type.atom("global"),
          Type.atom("trim"),
        ]);

        const result = split(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([Bitstring.fromText("a"), Bitstring.fromText("b")]),
        );
      });

      it("collects trailing bytes after loop exits naturally with global split", () => {
        const subject = Bitstring.fromText("a-b-c-");
        const pattern = Bitstring.fromText("-");
        const scope = Type.tuple([
          Type.atom("scope"),
          Type.tuple([Type.integer(0), Type.integer(5)]),
        ]);
        const options = Type.list([scope, Type.atom("global")]);

        const result = split(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([
            Bitstring.fromText("a"),
            Bitstring.fromText("b"),
            Bitstring.fromText("c-"),
          ]),
        );
      });

      it("collects trailing bytes when scope is exhausted in global split", () => {
        const subject = Bitstring.fromText("abcdef");
        const pattern = Bitstring.fromText("d");
        const scope = Type.tuple([
          Type.atom("scope"),
          Type.tuple([Type.integer(1), Type.integer(3)]),
        ]);
        const options = Type.list([scope, Type.atom("global")]);

        const result = split(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([Bitstring.fromText("abc"), Bitstring.fromText("ef")]),
        );
      });

      it("compiled Aho-Corasick pattern in split/3", () => {
        const subject = Bitstring.fromText("hello-world");
        const pattern = Type.list([
          Bitstring.fromText("-"),
          Bitstring.fromText("o"),
        ]);
        const compiledPattern = Erlang_Binary["compile_pattern/1"](pattern);
        const options = Type.list([Type.atom("global")]);

        const result = split(subject, compiledPattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([
            Bitstring.fromText("hell"),
            Bitstring.fromText(""),
            Bitstring.fromText("w"),
            Bitstring.fromText("rld"),
          ]),
        );
      });
    });

    describe("error cases", () => {
      it("raises ArgumentError when subject is not a binary", () => {
        const subject = Type.atom("test");
        const pattern = Bitstring.fromText(" ");
        const options = Type.list([]);

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a binary"),
        );
      });

      it("raises ArgumentError when subject is an integer", () => {
        const subject = Type.integer(123);
        const pattern = Bitstring.fromText(" ");
        const options = Type.list([]);

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a binary"),
        );
      });

      it("raises ArgumentError when subject is a non-binary bitstring", () => {
        const subject = Type.bitstring([1, 0, 1]);
        const pattern = Bitstring.fromText(" ");
        const options = Type.list([]);

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(
            1,
            "is a bitstring (expected a binary)",
          ),
        );
      });

      it("raises ArgumentError when options is not a list", () => {
        const subject = Bitstring.fromText("hello world");
        const pattern = Bitstring.fromText(" ");
        const options = Type.atom("invalid");

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          "invalid options",
        );
      });

      it("raises ArgumentError for improper list options", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("b");
        const options = Type.improperList([
          Type.atom("test"),
          Type.atom("tail"),
        ]);

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          "invalid options",
        );
      });

      it("raises ArgumentError for scope start beyond subject length", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("b");
        const scope = Type.tuple([
          Type.atom("scope"),
          Type.tuple([Type.integer(10), Type.integer(5)]),
        ]);
        const options = Type.list([scope]);

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          "invalid options",
        );
      });

      it("raises ArgumentError for negative scope length", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("b");
        const scope = Type.tuple([
          Type.atom("scope"),
          Type.tuple([Type.integer(0), Type.integer(-1)]),
        ]);
        const options = Type.list([scope]);

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          "invalid options",
        );
      });
    });
  });

  // TODO: consider
  // describe("_boyer_moore_search/3", () => {
  //   const subject = Bitstring.fromText("hello world");
  //   const pattern = Bitstring.fromText("hello");
  //   const search = Erlang_Binary["_boyer_moore_search/3"];
  //   Erlang_Binary["compile_pattern/1"](pattern);

  //   describe("with default options (empty list)", () => {
  //     it("finds pattern at the beginning of subject", () => {
  //       const result = search(subject, pattern, emptyList);
  //       assert.deepEqual(result, {index: 0, length: 5});
  //     });

  //     it("finds pattern in the middle of subject", () => {
  //       const altPattern = Bitstring.fromText("world");
  //       Erlang_Binary["compile_pattern/1"](altPattern);
  //       const result = search(subject, altPattern, emptyList);
  //       assert.deepEqual(result, {index: 6, length: 5});
  //     });

  //     it("returns false when pattern is not found", () => {
  //       const invalidSubject = Bitstring.fromText("goodbye");
  //       const result = search(invalidSubject, pattern, emptyList);
  //       assert.equal(result, false);
  //     });
  //   });

  //   describe("with scope option", () => {
  //     it("finds pattern starting at specified index", () => {
  //       const altPattern = Bitstring.fromText("world");
  //       Erlang_Binary["compile_pattern/1"](altPattern);
  //       const options = Type.list([
  //         Type.tuple([
  //           Type.atom("scope"),
  //           Type.tuple([Type.integer(3), Type.integer(8)]),
  //         ]),
  //       ]);

  //       const result = search(subject, altPattern, options);
  //       assert.deepEqual(result, {index: 6, length: 5});
  //     });

  //     it("returns false when pattern is before scope start", () => {
  //       const options = Type.list([
  //         Type.tuple([
  //           Type.atom("scope"),
  //           Type.tuple([Type.integer(6), Type.integer(5)]),
  //         ]),
  //       ]);

  //       const result = search(subject, pattern, options);
  //       assert.equal(result, false);
  //     });
  //   });
  // });

  // TODO: consider
  // describe("_aho_corasick_search/3", () => {
  //   const search = Erlang_Binary["_aho_corasick_search/3"];
  //   const subject = Bitstring.fromText("she sells shells");
  //   const pattern1 = Bitstring.fromText("she");
  //   const pattern2 = Bitstring.fromText("shells");
  //   const patternList = Type.list([pattern1, pattern2]);
  //   Erlang_Binary["compile_pattern/1"](patternList);

  //   describe("with default options (empty list)", () => {
  //     it("finds first pattern in subject", () => {
  //       const result = search(subject, patternList, emptyList);
  //       assert.deepEqual(result, {index: 0, length: 3});
  //     });

  //     it("returns false when no patterns are found", () => {
  //       const invalidSubject = Bitstring.fromText("hello world");
  //       const result = search(invalidSubject, patternList, emptyList);
  //       assert.deepEqual(result, false);
  //     });
  //   });

  //   describe("with scope option", () => {
  //     it("searches within specified scope", () => {
  //       const options = Type.list([
  //         Type.tuple([
  //           Type.atom("scope"),
  //           Type.tuple([Type.integer(3), Type.integer(10)]),
  //         ]),
  //       ]);

  //       const result = search(subject, patternList, options);

  //       assert.deepEqual(result, {index: 10, length: 3});
  //     });
  //   });
  // });

  // TODO: consider
  // describe("_parse_search_opts/1", () => {
  //   const parseSearchOpts = Erlang_Binary["_parse_search_opts/1"];

  //   describe("with empty list (default options)", () => {
  //     it("returns default start and length values", () => {
  //       const result = parseSearchOpts(emptyList);
  //       assert.deepEqual(result, {start: 0, length: -1});
  //     });
  //   });

  //   describe("with scope option", () => {
  //     it("parses scope tuple with valid integers", () => {
  //       const options = Type.list([
  //         Type.tuple([
  //           Type.atom("scope"),
  //           Type.tuple([Type.integer(5), Type.integer(10)]),
  //         ]),
  //       ]);
  //       const result = parseSearchOpts(options);

  //       assert.deepEqual(result, {start: 5, length: 10});
  //     });

  //     it("returns zero start when scope start is negative", () => {
  //       const options = Type.list([
  //         Type.tuple([
  //           Type.atom("scope"),
  //           Type.tuple([Type.integer(5), Type.integer(10)]),
  //         ]),
  //       ]);
  //       const result = parseSearchOpts(options);

  //       assert.deepEqual(result, {start: 5, length: 10});
  //     });
  //   });

  //   describe("error cases", () => {
  //     it("raises FunctionClauseError when options is not a list", () => {
  //       const options = Type.atom("invalid");

  //       assertBoxedError(
  //         () => parseSearchOpts(options),
  //         "FunctionClauseError",
  //         /invalid options/,
  //       );
  //     });

  //     it("raises FunctionClauseError when options is an improper list", () => {
  //       const options = Type.improperList([
  //         Type.atom("test"),
  //         Type.atom("tail"),
  //       ]);

  //       assertBoxedError(
  //         () => parseSearchOpts(options),
  //         "FunctionClauseError",
  //         /invalid options/,
  //       );
  //     });

  //     it("raises FunctionClauseError when scope contains non-integers", () => {
  //       const options = Type.list([
  //         Type.tuple([
  //           Type.atom("scope"),
  //           Type.tuple([Type.atom("invalid"), Type.integer(10)]),
  //         ]),
  //       ]);

  //       assertBoxedError(
  //         () => parseSearchOpts(options),
  //         "FunctionClauseError",
  //         /invalid options/,
  //       );
  //     });
  //   });
  // });
});
