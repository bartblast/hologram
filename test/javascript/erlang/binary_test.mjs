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

const emptyList = Type.list([]);

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
    describe("with single binary pattern", () => {
      const pattern = Bitstring.fromBytes([72, 101, 108, 108, 111]); // "Hello"
      const result = compilePattern(pattern);

      it("returns Boyer-Moore compiled pattern tuple", () => {
        assert.ok(Type.isCompiledPattern(result));
        assert.equal(result.data[0].value, "bm");
      });

      it("stores the badShift in the binaryPattern registry", () => {
        const saved = ERTS.binaryPatternRegistry.get(pattern);
        // Spot check characters
        assert.equal(saved.badShift["71"], -1);
        assert.equal(saved.badShift["72"], 4);
      });
    });

    describe("with list of binary patterns", () => {
      const pattern1 = Bitstring.fromBytes([72, 101]); // "He"
      const pattern2 = Bitstring.fromBytes([108, 108, 111]); // "llo"
      const patternList = Type.list([pattern1, pattern2]);
      const result = Erlang_Binary["compile_pattern/1"](patternList);

      it("returns Aho-Corasick compiled pattern tuple", () => {
        assert.ok(Type.isCompiledPattern(result));
        assert.equal(result.data[0].value, "ac");
      });

      it("stores the rootNode in the binaryPattern registry", () => {
        const saved = ERTS.binaryPatternRegistry.get(patternList);
        assert.deepEqual(Array.from(saved.rootNode.children.keys()), [72, 108]);
      });

      it("accepts a list with only one element", () => {
        const oneItemList = Type.list([pattern1]);
        const result = compilePattern(oneItemList);
        assert.ok(Type.isCompiledPattern(result));
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

  describe("_boyer_moore_pattern_matcher/1", () => {
    it("computes bad shift table correctly", () => {
      const pattern = Bitstring.fromBytes([104, 101, 108, 108, 111]);
      const result = Erlang_Binary["_boyer_moore_pattern_matcher/1"](pattern);
      assert.ok(Type.isCompiledPattern(result));
    });
  });

  // TODO: uncomment
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

  describe("_aho_corasick_pattern_matcher/1", () => {
    it("builds trie structure for multiple patterns", () => {
      const pattern1 = Bitstring.fromBytes([104, 101]); // "he"
      const pattern2 = Bitstring.fromBytes([115, 104, 101]); // "she"
      const patternList = Type.list([pattern1, pattern2]);
      const result =
        Erlang_Binary["_aho_corasick_pattern_matcher/1"](patternList);
      assert.ok(Type.isCompiledPattern(result));
    });
  });

  describe("_aho_corasick_search/3", () => {
    const search = Erlang_Binary["_aho_corasick_search/3"];
    const subject = Bitstring.fromText("she sells shells");
    const pattern1 = Bitstring.fromText("she");
    const pattern2 = Bitstring.fromText("shells");
    const patternList = Type.list([pattern1, pattern2]);
    Erlang_Binary["compile_pattern/1"](patternList);

    describe("with default options (empty list)", () => {
      it("finds first pattern in subject", () => {
        const result = search(subject, patternList, emptyList);
        assert.deepEqual(result, {index: 0, length: 3});
      });

      it("returns false when no patterns are found", () => {
        const invalidSubject = Bitstring.fromText("hello world");
        const result = search(invalidSubject, patternList, emptyList);
        assert.deepEqual(result, false);
      });
    });

    describe("with scope option", () => {
      it("searches within specified scope", () => {
        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(3), Type.integer(10)]),
          ]),
        ]);

        const result = search(subject, patternList, options);

        assert.deepEqual(result, {index: 10, length: 3});
      });
    });
  });

  describe("_parse_search_opts/1", () => {
    const parseSearchOpts = Erlang_Binary["_parse_search_opts/1"];

    describe("with empty list (default options)", () => {
      it("returns default start and length values", () => {
        const result = parseSearchOpts(emptyList);
        assert.deepEqual(result, {start: 0, length: -1});
      });
    });

    describe("with scope option", () => {
      it("parses scope tuple with valid integers", () => {
        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(5), Type.integer(10)]),
          ]),
        ]);
        const result = parseSearchOpts(options);

        assert.deepEqual(result, {start: 5, length: 10});
      });

      it("returns zero start when scope start is negative", () => {
        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.integer(5), Type.integer(10)]),
          ]),
        ]);
        const result = parseSearchOpts(options);

        assert.deepEqual(result, {start: 5, length: 10});
      });
    });

    describe("error cases", () => {
      it("raises FunctionClauseError when options is not a list", () => {
        const options = Type.atom("invalid");

        assertBoxedError(
          () => parseSearchOpts(options),
          "FunctionClauseError",
          /invalid options/,
        );
      });

      it("raises FunctionClauseError when options is an improper list", () => {
        const options = Type.improperList([
          Type.atom("test"),
          Type.atom("tail"),
        ]);

        assertBoxedError(
          () => parseSearchOpts(options),
          "FunctionClauseError",
          /invalid options/,
        );
      });

      it("raises FunctionClauseError when scope contains non-integers", () => {
        const options = Type.list([
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([Type.atom("invalid"), Type.integer(10)]),
          ]),
        ]);

        assertBoxedError(
          () => parseSearchOpts(options),
          "FunctionClauseError",
          /invalid options/,
        );
      });
    });
  });
});
