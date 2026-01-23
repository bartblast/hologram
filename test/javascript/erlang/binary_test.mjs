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

  describe("part/2", () => {
    const part2 = Erlang_Binary["part/2"];

    it("returns part of binary with tuple {start, length}", () => {
      const result = part2(
        Type.bitstring("hello world"),
        Type.tuple([Type.integer(0), Type.integer(5)]),
      );
      assertBoxedStrictEqual(result, Bitstring.fromText("hello"));
    });

    it("returns middle part with tuple", () => {
      const result = part2(
        Type.bitstring("hello world"),
        Type.tuple([Type.integer(6), Type.integer(5)]),
      );
      assertBoxedStrictEqual(result, Bitstring.fromText("world"));
    });

    it("returns empty binary when length is 0", () => {
      const result = part2(
        Type.bitstring("hello"),
        Type.tuple([Type.integer(0), Type.integer(0)]),
      );
      assertBoxedStrictEqual(result, Bitstring.fromText(""));
    });

    it("returns last character", () => {
      const result = part2(
        Type.bitstring("hello"),
        Type.tuple([Type.integer(4), Type.integer(1)]),
      );
      assertBoxedStrictEqual(result, Bitstring.fromText("o"));
    });

    it("handles bytes-based binary", () => {
      const binary = Bitstring.fromBytes([72, 101, 108, 108, 111]);
      const result = part2(
        binary,
        Type.tuple([Type.integer(1), Type.integer(3)]),
      );
      assertBoxedStrictEqual(result, Bitstring.fromText("ell"));
    });

    it("handles invalid UTF-8 bytes", () => {
      const binary = Bitstring.fromBytes([0xc3, 0x28, 0x41]);
      const result = part2(
        binary,
        Type.tuple([Type.integer(0), Type.integer(3)]),
      );
      assertBoxedStrictEqual(result, binary);
    });

    it("raises ArgumentError when subject is not a binary", () => {
      assertBoxedError(
        () =>
          part2(
            Type.atom("notabinary"),
            Type.tuple([Type.integer(0), Type.integer(1)]),
          ),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError when subject is a non-binary bitstring", () => {
      assertBoxedError(
        () =>
          part2(
            Type.bitstring([1, 0, 1]),
            Type.tuple([Type.integer(0), Type.integer(1)]),
          ),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError when posLen is not a tuple", () => {
      assertBoxedError(
        () =>
          part2(
            Type.bitstring("hello"),
            Type.list([Type.integer(0), Type.integer(1)]),
          ),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError when tuple has wrong length", () => {
      assertBoxedError(
        () => part2(Type.bitstring("hello"), Type.tuple([Type.integer(0)])),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError when start is not an integer", () => {
      assertBoxedError(
        () =>
          part2(
            Type.bitstring("hello"),
            Type.tuple([Type.atom("invalid"), Type.integer(1)]),
          ),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError when length is not an integer", () => {
      assertBoxedError(
        () =>
          part2(
            Type.bitstring("hello"),
            Type.tuple([Type.integer(0), Type.atom("invalid")]),
          ),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError when start is negative", () => {
      assertBoxedError(
        () =>
          part2(
            Type.bitstring("hello"),
            Type.tuple([Type.integer(-1), Type.integer(2)]),
          ),
        "ArgumentError",
        "argument error",
      );
    });

    it("extracts backwards with negative length", () => {
      const result = part2(
        Type.bitstring("hello"),
        Type.tuple([Type.integer(5), Type.integer(-3)]),
      );
      assertBoxedStrictEqual(result, Bitstring.fromText("llo"));
    });

    it("raises ArgumentError when part extends past end", () => {
      assertBoxedError(
        () =>
          part2(
            Type.bitstring("hello"),
            Type.tuple([Type.integer(2), Type.integer(10)]),
          ),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError when negative length goes before start", () => {
      assertBoxedError(
        () =>
          part2(
            Type.bitstring("hello"),
            Type.tuple([Type.integer(2), Type.integer(-3)]),
          ),
        "ArgumentError",
        "argument error",
      );
    });
  });

  describe("part/3", () => {
    const part3 = Erlang_Binary["part/3"];

    it("returns part of binary starting at position with given length", () => {
      const result = part3(
        Type.bitstring("hello world"),
        Type.integer(0),
        Type.integer(5),
      );
      assertBoxedStrictEqual(result, Bitstring.fromText("hello"));
    });

    it("returns middle part of binary", () => {
      const result = part3(
        Type.bitstring("hello world"),
        Type.integer(6),
        Type.integer(5),
      );
      assertBoxedStrictEqual(result, Bitstring.fromText("world"));
    });

    it("returns empty binary when length is 0", () => {
      const result = part3(
        Type.bitstring("hello"),
        Type.integer(0),
        Type.integer(0),
      );
      assertBoxedStrictEqual(result, Bitstring.fromText(""));
    });

    it("returns last character", () => {
      const result = part3(
        Type.bitstring("hello"),
        Type.integer(4),
        Type.integer(1),
      );
      assertBoxedStrictEqual(result, Bitstring.fromText("o"));
    });

    it("handles bytes-based binary", () => {
      const binary = Bitstring.fromBytes([72, 101, 108, 108, 111]);
      const result = part3(binary, Type.integer(1), Type.integer(3));
      assertBoxedStrictEqual(result, Bitstring.fromText("ell"));
    });

    it("handles invalid UTF-8 bytes", () => {
      const binary = Bitstring.fromBytes([0xc3, 0x28, 0x41]);
      const result = part3(binary, Type.integer(0), Type.integer(3));
      assertBoxedStrictEqual(result, binary);
    });

    it("raises ArgumentError when subject is not a binary", () => {
      assertBoxedError(
        () => part3(Type.atom("notabinary"), Type.integer(0), Type.integer(1)),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError when subject is a non-binary bitstring", () => {
      assertBoxedError(
        () =>
          part3(Type.bitstring([1, 0, 1]), Type.integer(0), Type.integer(1)),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError when start is not an integer", () => {
      assertBoxedError(
        () =>
          part3(Type.bitstring("hello"), Type.atom("invalid"), Type.integer(1)),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError when length is not an integer", () => {
      assertBoxedError(
        () =>
          part3(Type.bitstring("hello"), Type.integer(0), Type.atom("invalid")),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError when start is negative", () => {
      assertBoxedError(
        () => part3(Type.bitstring("hello"), Type.integer(-1), Type.integer(2)),
        "ArgumentError",
        "argument error",
      );
    });

    it("extracts backwards with negative length", () => {
      const result = part3(
        Type.bitstring("hello"),
        Type.integer(5),
        Type.integer(-3),
      );
      assertBoxedStrictEqual(result, Bitstring.fromText("llo"));
    });

    it("raises ArgumentError when part extends past end", () => {
      assertBoxedError(
        () => part3(Type.bitstring("hello"), Type.integer(2), Type.integer(10)),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError when negative length goes before start", () => {
      assertBoxedError(
        () => part3(Type.bitstring("hello"), Type.integer(2), Type.integer(-3)),
        "ArgumentError",
        "argument error",
      );
    });
  });
});
