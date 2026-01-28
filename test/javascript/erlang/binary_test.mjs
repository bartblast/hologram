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
// const emptyList = Type.list();

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
          Interpreter.buildArgumentErrorMsg(1, "not a valid pattern"),
        );
      });

      it("raises ArgumentError when pattern is non-binary bitstring", () => {
        assertBoxedError(
          () => compilePattern(Type.bitstring([1, 0, 1])),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a valid pattern"),
        );
      });

      it("raises ArgumentError when pattern is empty binary", () => {
        assertBoxedError(
          () => compilePattern(Type.bitstring("")),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a valid pattern"),
        );
      });

      it("raises ArgumentError when pattern is empty list", () => {
        assertBoxedError(
          () => compilePattern(Type.list()),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a valid pattern"),
        );
      });
    });

    describe("errors with list containing invalid item", () => {
      it("raises ArgumentError when pattern is list containing non-bitstring", () => {
        assertBoxedError(
          () => compilePattern(Type.list([patternHello, Type.integer(1)])),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a valid pattern"),
        );
      });

      it("raises ArgumentError when pattern is list containing non-binary bitstring", () => {
        assertBoxedError(
          () =>
            compilePattern(
              Type.list([patternHello, Type.bitstring([1, 0, 1])]),
            ),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a valid pattern"),
        );
      });

      it("raises ArgumentError when pattern is list containing empty binary", () => {
        assertBoxedError(
          () => compilePattern(Type.list([patternHello, Type.bitstring("")])),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a valid pattern"),
        );
      });

      it("raises ArgumentError when pattern is list containing empty list", () => {
        assertBoxedError(
          () => compilePattern(Type.list([patternHello, Type.list()])),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a valid pattern"),
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

  describe("match/2", () => {
    const match = Erlang_Binary["match/2"];

    it("delegates to match/3 with empty options", () => {
      const subject = Bitstring.fromText("hello world world");
      const pattern = Bitstring.fromText("world");
      const result = match(subject, pattern);

      // Verifies default options (no :global) - finds first match only
      assertBoxedStrictEqual(
        result,
        Type.tuple([Type.integer(6), Type.integer(5)]),
      );
    });
  });

  describe("match/3", () => {
    const match = Erlang_Binary["match/3"];

    describe("finding patterns", () => {
      it("finds single pattern at start", () => {
        const subject = Bitstring.fromText("the rain in spain");
        const pattern = Bitstring.fromText("the");
        const result = match(subject, pattern, Type.list());

        assertBoxedStrictEqual(
          result,
          Type.tuple([Type.integer(0), Type.integer(3)]),
        );
      });

      it("finds single pattern in middle", () => {
        const subject = Bitstring.fromText("the rain in spain");
        const pattern = Bitstring.fromText("ain");
        const result = match(subject, pattern, Type.list());

        assertBoxedStrictEqual(
          result,
          Type.tuple([Type.integer(5), Type.integer(3)]),
        );
      });

      it("finds single pattern at end", () => {
        const subject = Bitstring.fromText("hello world");
        const pattern = Bitstring.fromText("world");
        const result = match(subject, pattern, Type.list());

        assertBoxedStrictEqual(
          result,
          Type.tuple([Type.integer(6), Type.integer(5)]),
        );
      });

      it("returns nomatch when pattern not found", () => {
        const subject = Bitstring.fromText("hello world");
        const pattern = Bitstring.fromText("xyz");
        const result = match(subject, pattern, Type.list());

        assertBoxedStrictEqual(result, Type.atom("nomatch"));
      });

      it("finds first occurrence when multiple matches exist", () => {
        const subject = Bitstring.fromText("abcabc");
        const pattern = Bitstring.fromText("abc");
        const result = match(subject, pattern, Type.list());

        assertBoxedStrictEqual(
          result,
          Type.tuple([Type.integer(0), Type.integer(3)]),
        );
      });

      it("works with multi-byte patterns", () => {
        const subject = Bitstring.fromText("foo123bar");
        const pattern = Bitstring.fromText("123");
        const result = match(subject, pattern, Type.list());

        assertBoxedStrictEqual(
          result,
          Type.tuple([Type.integer(3), Type.integer(3)]),
        );
      });

      it("finds first match with multiple patterns", () => {
        const subject = Bitstring.fromText("abcde");

        const pattern = Type.list([
          Bitstring.fromText("bcde"),
          Bitstring.fromText("cd"),
        ]);

        const result = match(subject, pattern, Type.list());

        assertBoxedStrictEqual(
          result,
          Type.tuple([Type.integer(1), Type.integer(4)]),
        );
      });

      it("returns longest match when patterns start at same position", () => {
        const subject = Bitstring.fromText("abcde");

        const pattern = Type.list([
          Bitstring.fromText("ab"),
          Bitstring.fromText("abcd"),
        ]);

        const result = match(subject, pattern, Type.list());

        assertBoxedStrictEqual(
          result,
          Type.tuple([Type.integer(0), Type.integer(4)]),
        );
      });

      it("returns longest match with three or more overlapping patterns", () => {
        const subject = Bitstring.fromText("abcdefgh");

        const pattern = Type.list([
          Bitstring.fromText("ab"),
          Bitstring.fromText("abc"),
          Bitstring.fromText("abcd"),
          Bitstring.fromText("abcde"),
        ]);

        const result = match(subject, pattern, Type.list());

        assertBoxedStrictEqual(
          result,
          Type.tuple([Type.integer(0), Type.integer(5)]),
        );
      });

      it("works with compiled pattern", () => {
        const subject = Bitstring.fromText("hello world");
        const pattern = Bitstring.fromText("world");
        const compiled = Erlang_Binary["compile_pattern/1"](pattern);
        const result = match(subject, compiled, Type.list());

        assertBoxedStrictEqual(
          result,
          Type.tuple([Type.integer(6), Type.integer(5)]),
        );
      });

      it("works with bytes-based binary", () => {
        const subject = Bitstring.fromBytes([1, 2, 3, 4, 5]);
        const pattern = Bitstring.fromBytes([3, 4]);
        const result = match(subject, pattern, Type.list());

        assertBoxedStrictEqual(
          result,
          Type.tuple([Type.integer(2), Type.integer(2)]),
        );
      });

      it("returns nomatch when subject is empty", () => {
        const subject = Bitstring.fromText("");
        const pattern = Bitstring.fromText("a");
        const result = match(subject, pattern, Type.list());

        assertBoxedStrictEqual(result, Type.atom("nomatch"));
      });

      it("returns nomatch when pattern is longer than subject", () => {
        const subject = Bitstring.fromText("ab");
        const pattern = Bitstring.fromText("abcdef");
        const result = match(subject, pattern, Type.list());

        assertBoxedStrictEqual(result, Type.atom("nomatch"));
      });
    });

    describe("scope option - valid cases", () => {
      it("returns nomatch when pattern exists but not within scope", () => {
        const subject = Bitstring.fromText("hello world");
        const pattern = Bitstring.fromText("world");

        const options = Type.list([
          Type.tuple([Type.atom("scope"), Type.tuple([integer0, integer3])]),
        ]);

        const result = match(subject, pattern, options);

        assertBoxedStrictEqual(result, Type.atom("nomatch"));
      });

      it("respects scope start position", () => {
        const subject = Bitstring.fromText("the rain in spain");
        const pattern = Bitstring.fromText("ain");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(5), Type.integer(8)]),
          ]),
        ]);

        const result = match(subject, pattern, options);

        assertBoxedStrictEqual(
          result,
          Type.tuple([Type.integer(5), Type.integer(3)]),
        );
      });

      it("finds match at start of scope", () => {
        const subject = Bitstring.fromText("abcdef");
        const pattern = Bitstring.fromText("cd");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(2), Type.integer(4)]),
          ]),
        ]);

        const result = match(subject, pattern, options);

        assertBoxedStrictEqual(
          result,
          Type.tuple([Type.integer(2), Type.integer(2)]),
        );
      });

      it("returns nomatch when pattern outside scope", () => {
        const subject = Bitstring.fromText("hello world");
        const pattern = Bitstring.fromText("world");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([integer0, Type.integer(5)]),
          ]),
        ]);

        const result = match(subject, pattern, options);

        assertBoxedStrictEqual(result, Type.atom("nomatch"));
      });

      it("returns nomatch when scope length is zero", () => {
        const subject = Bitstring.fromText("hello");
        const pattern = Bitstring.fromText("h");

        const options = Type.list([
          Type.tuple([Type.atom("scope"), Type.tuple([integer0, integer0])]),
        ]);

        const result = match(subject, pattern, options);

        assertBoxedStrictEqual(result, Type.atom("nomatch"));
      });

      it("accepts negative scope length (reverse part)", () => {
        const subject = Bitstring.fromText("hello world");
        const pattern = Bitstring.fromText("world");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(11), Type.integer(-5)]),
          ]),
        ]);

        assert.deepStrictEqual(
          match(subject, pattern, options),
          Type.tuple([Type.integer(6), Type.integer(5)]),
        );
      });
    });

    describe("with empty options list", () => {
      it("works with empty options list", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Bitstring.fromText("es");
        const result = match(subject, pattern, Type.list());

        assertBoxedStrictEqual(
          result,
          Type.tuple([Type.integer(1), Type.integer(2)]),
        );
      });
    });

    describe("input validation", () => {
      it("raises ArgumentError if subject is not a binary", () => {
        const pattern = Bitstring.fromText("test");

        assertBoxedError(
          () => match(Type.atom("not_binary"), pattern, Type.list()),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a binary"),
        );
      });

      it("raises ArgumentError if subject is a non-binary bitstring", () => {
        const subject = Type.bitstring([1, 0, 1]);
        const pattern = Bitstring.fromText("test");

        assertBoxedError(
          () => match(subject, pattern, Type.list()),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(
            1,
            "is a bitstring (expected a binary)",
          ),
        );
      });

      it("raises ArgumentError when pattern is empty", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Bitstring.fromText("");

        assertBoxedError(
          () => match(subject, pattern, Type.list()),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises ArgumentError with empty pattern list", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Type.list();

        assertBoxedError(
          () => match(subject, pattern, Type.list()),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises ArgumentError if pattern is not a binary or list", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Type.atom("invalid");

        assertBoxedError(
          () => match(subject, pattern, Type.list()),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises ArgumentError if pattern list contains non-binary element", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Type.list([Bitstring.fromText("ok"), Type.atom("bad")]);

        assertBoxedError(
          () => match(subject, pattern, Type.list()),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises ArgumentError with invalid compiled pattern reference", () => {
        const subject = Bitstring.fromText("test");
        const invalidRef = Erlang["make_ref/0"]();
        const pattern = Type.tuple([Type.atom("bm"), invalidRef]);

        assertBoxedError(
          () => match(subject, pattern, Type.list()),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });
    });

    describe("options validation", () => {
      it("raises ArgumentError if options is not a list", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Bitstring.fromText("es");

        assertBoxedError(
          () => match(subject, pattern, Type.atom("invalid")),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError if options is an improper list", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Bitstring.fromText("es");

        const options = Type.improperList([
          Type.atom("global"),
          Type.atom("tail"),
        ]);

        assertBoxedError(
          () => match(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError with unknown atom option", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Bitstring.fromText("es");
        const options = Type.list([Type.atom("unknown")]);

        assertBoxedError(
          () => match(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError with malformed scope tuple", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Bitstring.fromText("es");

        const options = Type.list([
          Type.tuple([Type.atom("scope"), Type.atom("bad")]),
        ]);

        assertBoxedError(
          () => match(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError when scope start exceeds subject length", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Bitstring.fromText("t");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(10), integer1]),
          ]),
        ]);

        assertBoxedError(
          () => match(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError when scope extends beyond subject", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Bitstring.fromText("st");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([integer0, Type.integer(100)]),
          ]),
        ]);

        assertBoxedError(
          () => match(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError with negative scope start", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Bitstring.fromText("es");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(-1), Type.integer(2)]),
          ]),
        ]);

        assertBoxedError(
          () => match(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError when scope start plus negative length is below zero", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Bitstring.fromText("es");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(0), Type.integer(-1)]),
          ]),
        ]);

        assertBoxedError(
          () => match(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError with non-integer scope start", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Bitstring.fromText("es");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.atom("bad"), Type.integer(2)]),
          ]),
        ]);

        assertBoxedError(
          () => match(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError with non-integer scope length", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Bitstring.fromText("es");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(0), Type.atom("bad")]),
          ]),
        ]);

        assertBoxedError(
          () => match(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });
    });
  });

  describe("matches/2", () => {
    const matches = Erlang_Binary["matches/2"];

    it("delegates to matches/3 with empty options", () => {
      const subject = Bitstring.fromText("the rain in spain");
      const pattern = Bitstring.fromText("ai");

      const result = matches(subject, pattern);

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.tuple([Type.integer(5), Type.integer(2)]),
          Type.tuple([Type.integer(14), Type.integer(2)]),
        ]),
      );
    });
  });

  describe("matches/3", () => {
    const matches = Erlang_Binary["matches/3"];

    describe("finding patterns", () => {
      it("returns all non-overlapping matches", () => {
        const subject = Bitstring.fromText("banana bandana");
        const pattern = Bitstring.fromText("ana");

        const result = matches(subject, pattern, Type.list());

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.tuple([Type.integer(1), Type.integer(3)]),
            Type.tuple([Type.integer(11), Type.integer(3)]),
          ]),
        );
      });

      it("returns non-overlapping repeated matches", () => {
        const subject = Bitstring.fromText("aaaa");
        const pattern = Bitstring.fromText("aa");

        const result = matches(subject, pattern, Type.list());

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.tuple([Type.integer(0), Type.integer(2)]),
            Type.tuple([Type.integer(2), Type.integer(2)]),
          ]),
        );
      });

      it("prefers longer match when starting at same position", () => {
        const subject = Bitstring.fromText("abcde");

        const pattern = Type.list([
          Bitstring.fromText("bcde"),
          Bitstring.fromText("bc"),
          Bitstring.fromText("de"),
        ]);

        const result = matches(subject, pattern, Type.list());

        assert.deepStrictEqual(
          result,
          Type.list([Type.tuple([Type.integer(1), Type.integer(4)])]),
        );
      });

      it("works with compiled pattern", () => {
        const subject = Bitstring.fromText("the rain in spain");
        const pattern = Bitstring.fromText("ai");
        const compiled = Erlang_Binary["compile_pattern/1"](pattern);

        const result = matches(subject, compiled, Type.list());

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.tuple([Type.integer(5), Type.integer(2)]),
            Type.tuple([Type.integer(14), Type.integer(2)]),
          ]),
        );
      });

      it("works with bytes-based binary", () => {
        const subject = Bitstring.fromBytes([1, 2, 3, 2, 3, 4]);
        const pattern = Bitstring.fromBytes([2, 3]);

        const result = matches(subject, pattern, Type.list());

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.tuple([Type.integer(1), Type.integer(2)]),
            Type.tuple([Type.integer(3), Type.integer(2)]),
          ]),
        );
      });

      it("works with compiled Aho-Corasick pattern", () => {
        const subject = Bitstring.fromText("zabcbc");

        const pattern = Type.list([
          Bitstring.fromText("ab"),
          Bitstring.fromText("bc"),
        ]);

        const compiled = Erlang_Binary["compile_pattern/1"](pattern);
        const result = matches(subject, compiled, Type.list());

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.tuple([Type.integer(1), Type.integer(2)]),
            Type.tuple([Type.integer(4), Type.integer(2)]),
          ]),
        );
      });

      it("returns empty list when no matches", () => {
        const subject = Bitstring.fromText("hello");
        const pattern = Bitstring.fromText("xyz");

        const result = matches(subject, pattern, Type.list());

        assert.deepStrictEqual(result, Type.list());
      });

      it("returns empty list when subject is empty", () => {
        const subject = Bitstring.fromText("");
        const pattern = Bitstring.fromText("a");

        const result = matches(subject, pattern, Type.list());

        assert.deepStrictEqual(result, Type.list());
      });

      it("returns empty list when pattern is longer than subject", () => {
        const subject = Bitstring.fromText("ab");
        const pattern = Bitstring.fromText("abcdef");

        const result = matches(subject, pattern, Type.list());

        assert.deepStrictEqual(result, Type.list());
      });
    });

    describe("scope option", () => {
      it("finds matches only within scope", () => {
        const subject = Bitstring.fromText("the rain in spain");
        const pattern = Bitstring.fromText("ai");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(4), Type.integer(6)]),
          ]),
        ]);

        const result = matches(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([Type.tuple([Type.integer(5), Type.integer(2)])]),
        );
      });

      it("returns empty list when scope length is zero", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("a");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(0), Type.integer(0)]),
          ]),
        ]);

        const result = matches(subject, pattern, options);

        assert.deepStrictEqual(result, Type.list());
      });

      it("supports negative scope length", () => {
        const subject = Bitstring.fromText("hello world");
        const pattern = Bitstring.fromText("wo");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(11), Type.integer(-5)]),
          ]),
        ]);

        const result = matches(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([Type.tuple([Type.integer(6), Type.integer(2)])]),
        );
      });
    });

    describe("input validation", () => {
      it("raises ArgumentError if subject is not a binary", () => {
        const pattern = Bitstring.fromText("a");

        assertBoxedError(
          () => matches(Type.atom("not_binary"), pattern, Type.list()),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a binary"),
        );
      });

      it("raises ArgumentError if subject is a non-binary bitstring", () => {
        const subject = Type.bitstring([1, 0, 1]);
        const pattern = Bitstring.fromText("a");

        assertBoxedError(
          () => matches(subject, pattern, Type.list()),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(
            1,
            "is a bitstring (expected a binary)",
          ),
        );
      });

      it("raises ArgumentError when pattern is invalid", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("");

        assertBoxedError(
          () => matches(subject, pattern, Type.list()),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises ArgumentError with empty pattern list", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Type.list();

        assertBoxedError(
          () => matches(subject, pattern, Type.list()),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises ArgumentError if pattern list contains non-binary element", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Type.list([Bitstring.fromText("ok"), Type.atom("bad")]);

        assertBoxedError(
          () => matches(subject, pattern, Type.list()),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises ArgumentError with missing compiled pattern data", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("a");
        const compiled = Erlang_Binary["compile_pattern/1"](pattern);
        const ref = compiled.data[1];
        const key = Type.encodeMapKey(ref);
        ERTS.binaryPatternRegistry.patterns.delete(key);

        assertBoxedError(
          () => matches(subject, compiled, Type.list()),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });
    });

    describe("options validation", () => {
      it("raises ArgumentError if options is not a list", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("a");

        assertBoxedError(
          () => matches(subject, pattern, Type.atom("bad")),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError for improper list options", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("a");

        const options = Type.improperList([
          Type.atom("scope"),
          Type.atom("tail"),
        ]);

        assertBoxedError(
          () => matches(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError when unsupported option provided", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("a");
        const options = Type.list([Type.atom("global")]);

        assertBoxedError(
          () => matches(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError with malformed scope", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("a");

        const options = Type.list([
          Type.tuple([Type.atom("scope"), Type.atom("bad")]),
        ]);

        assertBoxedError(
          () => matches(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError when scope is out of range", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("a");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(10), Type.integer(1)]),
          ]),
        ]);

        assertBoxedError(
          () => matches(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError when scope extends beyond subject", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("a");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(0), Type.integer(10)]),
          ]),
        ]);

        assertBoxedError(
          () => matches(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError when scope start is negative", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("a");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(-1), Type.integer(2)]),
          ]),
        ]);

        assertBoxedError(
          () => matches(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError when scope start plus negative length is below zero", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("a");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(0), Type.integer(-1)]),
          ]),
        ]);

        assertBoxedError(
          () => matches(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError when scope length is not an integer", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("a");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(0), Type.atom("bad")]),
          ]),
        ]);

        assertBoxedError(
          () => matches(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError when scope elements are not integers", () => {
        const subject = Bitstring.fromText("abc");
        const pattern = Bitstring.fromText("a");

        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.atom("bad"), Type.integer(1)]),
          ]),
        ]);

        assertBoxedError(
          () => matches(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });
    });
  });

  describe("split/2", () => {
    const split = Erlang_Binary["split/2"];

    it("delegates to split/3 with empty options", () => {
      const subject = Bitstring.fromText("hello world world");
      const pattern = Bitstring.fromText(" ");
      const result = split(subject, pattern);

      // Verifies default options (no :global) - splits only on first match
      assert.deepStrictEqual(
        result,
        Type.list([
          Bitstring.fromText("hello"),
          Bitstring.fromText("world world"),
        ]),
      );
    });
  });

  describe("split/3", () => {
    const split = Erlang_Binary["split/3"];

    describe("with :global option", () => {
      it("splits on all occurrences with :global", () => {
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

      it("handles consecutive patterns with :global", () => {
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

      it("handles invalid UTF-8 sequences in result with :global", () => {
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
      it("splits only on first occurrence without :global", () => {
        const subject = Bitstring.fromText("hello-world-test");
        const pattern = Bitstring.fromText("-");
        const options = Type.list();
        const result = split(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([
            Bitstring.fromText("hello"),
            Bitstring.fromText("world-test"),
          ]),
        );
      });

      it("splits with multi-byte pattern", () => {
        const subject = Bitstring.fromText("aaabbbccc");
        const pattern = Bitstring.fromText("bb");
        const options = Type.list();
        const result = split(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([Bitstring.fromText("aaa"), Bitstring.fromText("bccc")]),
        );
      });

      it("returns list with original binary when pattern not found", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Bitstring.fromText("x");
        const options = Type.list();
        const result = split(subject, pattern, options);

        assert.deepStrictEqual(result, Type.list([Bitstring.fromText("test")]));
      });

      it("splits with multiple patterns", () => {
        const subject = Bitstring.fromText("hello-world_test");

        const pattern = Type.list([
          Bitstring.fromText("-"),
          Bitstring.fromText("_"),
        ]);

        const options = Type.list();

        const result = split(subject, pattern, options);

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
        const options = Type.list();
        const result = split(subject, pattern, options);

        assert.deepStrictEqual(result, Type.list([Bitstring.fromText("")]));
      });
    });

    describe("compiled pattern behavior", () => {
      beforeEach(() => {
        ERTS.binaryPatternRegistry.patterns.clear();
      });

      it("splits using compiled Boyer-Moore pattern", () => {
        const subject = Bitstring.fromText("hello world");
        const pattern = Bitstring.fromText("world");
        const compiledPattern = Erlang_Binary["compile_pattern/1"](pattern);
        const options = Type.list();

        const result = split(subject, compiledPattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([Bitstring.fromText("hello "), Bitstring.fromText("")]),
        );
      });

      it("splits using compiled Aho-Corasick pattern", () => {
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

      it("raises ArgumentError when compiled pattern data is missing", () => {
        const subject = Bitstring.fromText("hello");
        const pattern = Bitstring.fromText("ell");
        const compiledPattern = Erlang_Binary["compile_pattern/1"](pattern);
        const patternRef = compiledPattern.data[1];
        const patternKey = Type.encodeMapKey(patternRef);
        ERTS.binaryPatternRegistry.patterns.delete(patternKey);

        const options = Type.list();

        assertBoxedError(
          () => split(subject, compiledPattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });
    });

    describe("options: :trim and :trim_all", () => {
      it("applies :trim to remove trailing empties only", () => {
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

      it("returns empty list when empty subject with :trim", () => {
        const subject = Bitstring.fromText("");
        const pattern = Bitstring.fromText(" ");
        const options = Type.list([Type.atom("global"), Type.atom("trim")]);
        const result = split(subject, pattern, options);

        assert.deepStrictEqual(result, Type.list());
      });
    });

    describe("options: scope", () => {
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

      it("returns original binary when scope length is zero", () => {
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

      it("works with scope and multiple patterns", () => {
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

      it("works with scope and :trim option", () => {
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

      it("accepts negative scope length (reverse part)", () => {
        const subject = Bitstring.fromText("hello world");
        const pattern = Bitstring.fromText(" ");

        const scope = Type.tuple([
          Type.atom("scope"),
          Type.tuple([Type.integer(11), Type.integer(-6)]),
        ]);

        const options = Type.list([scope]);

        const result = split(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([Bitstring.fromText("hello"), Bitstring.fromText("world")]),
        );
      });
    });

    describe("overlapping patterns", () => {
      it("with overlapping patterns, matches first found", () => {
        const subject = Bitstring.fromText("abcabc");

        const pattern = Type.list([
          Bitstring.fromText("ab"),
          Bitstring.fromText("abc"),
        ]);

        const options = Type.list([Type.atom("global")]);

        const result = split(subject, pattern, options);

        assert.deepStrictEqual(
          result,
          Type.list([
            Bitstring.fromText(""),
            Bitstring.fromText(""),
            Bitstring.fromText(""),
          ]),
        );
      });
    });

    describe("error cases", () => {
      it("raises ArgumentError when subject is not bitstring", () => {
        const subject = Type.atom("test");
        const pattern = Bitstring.fromText(" ");
        const options = Type.list();

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a binary"),
        );
      });

      it("raises ArgumentError when subject is non-binary bitstring", () => {
        const subject = Type.bitstring([1, 0, 1]);
        const pattern = Bitstring.fromText(" ");
        const options = Type.list();

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(
            1,
            "is a bitstring (expected a binary)",
          ),
        );
      });

      it("raises ArgumentError when pattern is not bitstring", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Type.integer(123);
        const options = Type.list();

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises ArgumentError when pattern is non-binary bitstring", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Type.bitstring([1, 0, 1]);
        const options = Type.list();

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises ArgumentError when pattern is empty string", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Bitstring.fromText("");
        const options = Type.list();

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises ArgumentError when pattern is empty list", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Type.list();
        const options = Type.list();

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises ArgumentError when pattern is list with non-bitstring", () => {
        const subject = Bitstring.fromText("test");
        const pattern = Type.list([Bitstring.fromText("a"), Type.atom("b")]);
        const options = Type.list();

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises ArgumentError when pattern is list with non-binary bitstring", () => {
        const subject = Bitstring.fromText("test");

        const pattern = Type.list([
          Bitstring.fromText("a"),
          Type.bitstring([1, 0, 1]),
        ]);

        const options = Type.list();

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises ArgumentError when pattern is list with empty string", () => {
        const subject = Bitstring.fromText("test");

        const pattern = Type.list([
          Bitstring.fromText("a"),
          Bitstring.fromText(""),
        ]);

        const options = Type.list();

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      });

      it("raises ArgumentError when options is not a list", () => {
        const subject = Bitstring.fromText("hello world");
        const pattern = Bitstring.fromText(" ");
        const options = Type.atom("invalid");

        assertBoxedError(
          () => split(subject, pattern, options),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
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
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
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
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
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
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });

      it("raises ArgumentError for scope extending beyond subject length", () => {
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
          Interpreter.buildArgumentErrorMsg(3, "invalid options"),
        );
      });
    });
  });
});
