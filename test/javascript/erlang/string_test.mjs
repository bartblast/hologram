"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang_String from "../../../assets/js/erlang/string.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/string_test.exs
// Always update both together.

describe("Erlang_String", () => {
  describe("find/2", () => {
    const testedFun = Erlang_String["find/2"];

    it("delegates to find/3 with :leading direction", () => {
      const string = Type.bitstring("ab..cd..ef");
      const pattern = Type.bitstring("..");

      assert.deepStrictEqual(
        testedFun(string, pattern),
        Erlang_String["find/3"](string, pattern, Type.atom("leading")),
      );
    });
  });

  describe("find/3", () => {
    const find = Erlang_String["find/3"];

    describe("direction variations", () => {
      it("with direction :leading finds first occurrence", () => {
        const result = find(
          Type.bitstring("ab..cd..ef"),
          Type.bitstring(".."),
          Type.atom("leading"),
        );

        assert.deepStrictEqual(result, Type.bitstring("..cd..ef"));
      });

      it("with direction :trailing finds last occurrence", () => {
        const result = find(
          Type.bitstring("ab..cd..ef"),
          Type.bitstring(".."),
          Type.atom("trailing"),
        );

        assert.deepStrictEqual(result, Type.bitstring("..ef"));
      });
    });

    describe("pattern not found", () => {
      it("returns :nomatch with :leading direction", () => {
        const result = find(
          Type.bitstring("ab..cd..ef"),
          Type.bitstring("x"),
          Type.atom("leading"),
        );

        assert.deepStrictEqual(result, Type.atom("nomatch"));
      });

      it("returns :nomatch with :trailing direction", () => {
        const result = find(
          Type.bitstring("ab..cd..ef"),
          Type.bitstring("x"),
          Type.atom("trailing"),
        );

        assert.deepStrictEqual(result, Type.atom("nomatch"));
      });
    });

    describe("pattern position edge cases", () => {
      it("when pattern is at the start of the string", () => {
        const result = find(
          Type.bitstring("..abcd"),
          Type.bitstring(".."),
          Type.atom("leading"),
        );

        assert.deepStrictEqual(result, Type.bitstring("..abcd"));
      });

      it("when pattern is at the end of the string", () => {
        const result = find(
          Type.bitstring("abcd.."),
          Type.bitstring(".."),
          Type.atom("trailing"),
        );

        assert.deepStrictEqual(result, Type.bitstring(".."));
      });

      it("with single character pattern", () => {
        const result = find(
          Type.bitstring("ab..cd..ef"),
          Type.bitstring("."),
          Type.atom("leading"),
        );

        assert.deepStrictEqual(result, Type.bitstring("..cd..ef"));
      });
    });

    describe("input edge cases", () => {
      it("with empty pattern returns string as-is", () => {
        const result = find(
          Type.bitstring("Hello World"),
          Type.bitstring(""),
          Type.atom("leading"),
        );

        assert.deepStrictEqual(result, Type.bitstring("Hello World"));
      });

      it("with empty string and empty pattern", () => {
        const result = find(
          Type.bitstring(""),
          Type.bitstring(""),
          Type.atom("leading"),
        );

        assert.deepStrictEqual(result, Type.bitstring(""));
      });

      it("with empty string and non-empty pattern", () => {
        const result = find(
          Type.bitstring(""),
          Type.bitstring("x"),
          Type.atom("leading"),
        );

        assert.deepStrictEqual(result, Type.atom("nomatch"));
      });

      it("with unicode pattern", () => {
        const result = find(
          Type.bitstring("Hello 👋 World 👋 End"),
          Type.bitstring("👋"),
          Type.atom("trailing"),
        );

        assert.deepStrictEqual(result, Type.bitstring("👋 End"));
      });

      it("when pattern equals string", () => {
        const result = find(
          Type.bitstring("abc"),
          Type.bitstring("abc"),
          Type.atom("leading"),
        );

        assert.deepStrictEqual(result, Type.bitstring("abc"));
      });
    });

    describe("charlist input", () => {
      it("with charlist string and charlist pattern", () => {
        const result = find(
          Type.charlist("ab..cd..ef"),
          Type.charlist(".."),
          Type.atom("leading"),
        );

        assert.deepStrictEqual(result, Type.charlist("..cd..ef"));
      });

      it("with charlist string and binary pattern", () => {
        const result = find(
          Type.charlist("ab..cd..ef"),
          Type.bitstring(".."),
          Type.atom("trailing"),
        );

        assert.deepStrictEqual(result, Type.charlist("..ef"));
      });

      it("with binary string and charlist pattern", () => {
        const result = find(
          Type.bitstring("ab..cd..ef"),
          Type.charlist(".."),
          Type.atom("leading"),
        );

        assert.deepStrictEqual(result, Type.bitstring("..cd..ef"));
      });

      it("returns :nomatch for charlist when pattern not found", () => {
        const result = find(
          Type.charlist("ab..cd..ef"),
          Type.charlist("x"),
          Type.atom("leading"),
        );

        assert.deepStrictEqual(result, Type.atom("nomatch"));
      });

      it("with empty pattern returns charlist as-is", () => {
        const result = find(
          Type.charlist("Hello World"),
          Type.charlist(""),
          Type.atom("leading"),
        );

        assert.deepStrictEqual(result, Type.charlist("Hello World"));
      });
    });

    describe("error cases", () => {
      it("raises MatchError if the first argument is not valid chardata", () => {
        const invalidArg = Type.atom("abc");

        assertBoxedError(
          () => find(invalidArg, Type.bitstring("_"), Type.atom("leading")),
          "MatchError",
          Interpreter.buildMatchErrorMsg(invalidArg),
        );
      });

      it("raises MatchError if the first argument is a non-binary bitstring", () => {
        const nonBinaryBitstring = Type.bitstring([1, 0, 1]);

        assertBoxedError(
          () =>
            find(nonBinaryBitstring, Type.bitstring("x"), Type.atom("leading")),
          "MatchError",
          Interpreter.buildMatchErrorMsg(nonBinaryBitstring),
        );
      });

      it("raises ArgumentError if the second argument is not valid chardata", () => {
        assertBoxedError(
          () =>
            find(
              Type.bitstring("Hello World"),
              Type.atom("abc"),
              Type.atom("leading"),
            ),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(
            1,
            "not valid character data (an iodata term)",
          ),
        );
      });

      it("raises ArgumentError if the second argument is a non-binary bitstring", () => {
        assertBoxedError(
          () =>
            find(
              Type.bitstring("Hello World"),
              Type.bitstring([1, 0, 1]),
              Type.atom("leading"),
            ),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(
            1,
            "not valid character data (an iodata term)",
          ),
        );
      });

      it("raises FunctionClauseError if the third argument is not an atom", () => {
        assertBoxedError(
          () =>
            find(
              Type.bitstring("Hello World"),
              Type.bitstring(" "),
              Type.bitstring("leading"),
            ),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":string.find/3", [
            Type.bitstring("Hello World"),
            Type.bitstring(" "),
            Type.bitstring("leading"),
          ]),
        );
      });

      it("raises FunctionClauseError if the third argument is an unrecognized atom", () => {
        assertBoxedError(
          () =>
            find(
              Type.bitstring("Hello World"),
              Type.bitstring(" "),
              Type.atom("all"),
            ),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":string.find/3", [
            Type.bitstring("Hello World"),
            Type.bitstring(" "),
            Type.atom("all"),
          ]),
        );
      });
    });
  });

  describe("join/2", () => {
    const join = Erlang_String["join/2"];

    it("single element", () => {
      const list = Type.list([Type.charlist("hello")]);
      const separator = Type.charlist(", ");

      const result = join(list, separator);
      const expected = Type.charlist("hello");

      assert.deepStrictEqual(result, expected);
    });

    it("multiple elements", () => {
      const list = Type.list([
        Type.charlist("one"),
        Type.charlist("two"),
        Type.charlist("three"),
      ]);

      const separator = Type.charlist(", ");

      const result = join(list, separator);
      const expected = Type.charlist("one, two, three");

      assert.deepStrictEqual(result, expected);
    });

    it("no elements", () => {
      const list = Type.list();
      const separator = Type.charlist(", ");

      const result = join(list, separator);
      const expected = Type.list();

      assert.deepStrictEqual(result, expected);
    });

    it("single-character separator", () => {
      const list = Type.list([
        Type.charlist("apple"),
        Type.charlist("banana"),
        Type.charlist("cherry"),
      ]);

      const separator = Type.charlist(",");

      const result = join(list, separator);
      const expected = Type.charlist("apple,banana,cherry");

      assert.deepStrictEqual(result, expected);
    });

    it("multi-character separator", () => {
      const list = Type.list([
        Type.charlist("apple"),
        Type.charlist("banana"),
        Type.charlist("cherry"),
      ]);

      const separator = Type.charlist(" and ");

      const result = join(list, separator);
      const expected = Type.charlist("apple and banana and cherry");

      assert.deepStrictEqual(result, expected);
    });

    it("empty separator", () => {
      const list = Type.list([Type.charlist("hello"), Type.charlist("world")]);

      const separator = Type.charlist("");

      const result = join(list, separator);
      const expected = Type.charlist("helloworld");

      assert.deepStrictEqual(result, expected);
    });

    it("empty charlists in list", () => {
      const list = Type.list([
        Type.charlist(""),
        Type.charlist("hello"),
        Type.charlist(""),
        Type.charlist("world"),
        Type.charlist(""),
      ]);

      const separator = Type.charlist("-");

      const result = join(list, separator);
      const expected = Type.charlist("-hello--world-");

      assert.deepStrictEqual(result, expected);
    });

    it("lists with non-integer elements", () => {
      const list = Type.list([
        Type.list([Type.atom("a"), Type.atom("b")]),
        Type.list([Type.atom("c"), Type.atom("d")]),
      ]);

      const separator = Type.charlist("abc");

      const result = join(list, separator);

      const expected = Type.list([
        Type.atom("a"),
        Type.atom("b"),
        Type.integer(97),
        Type.integer(98),
        Type.integer(99),
        Type.atom("c"),
        Type.atom("d"),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the first argument is not a list", () => {
      const list = Type.atom("not_a_list");
      const separator = Type.charlist(", ");

      assertBoxedError(
        () => join(list, separator),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":string.join/2", [
          list,
          separator,
        ]),
      );
    });

    it("raises ErlangError if the first argument is an improper list", () => {
      const list = Type.improperList([
        Type.charlist("hello"),
        Type.atom("tail"),
      ]);

      const separator = Type.charlist(", ");

      assertBoxedError(
        () => join(list, separator),
        "ErlangError",
        Interpreter.buildErlangErrorMsg("{:bad_generator, :tail}"),
      );
    });

    it("raises FunctionClauseError for empty list with non-list separator", () => {
      const list = Type.list();
      const separator = Type.atom("not_a_list");

      assertBoxedError(
        () => join(list, separator),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(":string.join/2", [
          list,
          separator,
        ]),
      );
    });

    it("raises ArgumentError for multiple elements with non-list separator", () => {
      const list = Type.list([Type.charlist("hello"), Type.charlist("world")]);

      const separator = Type.atom("not_a_list");

      assertBoxedError(
        () => join(list, separator),
        "ArgumentError",
        "argument error",
      );
    });
  });

  describe("length/1", () => {
    const length = Erlang_String["length/1"];

    describe("binary string input", () => {
      it("returns 0 for empty binary string", () => {
        assert.deepStrictEqual(length(Type.bitstring("")), Type.integer(0));
      });

      it("returns length of simple ASCII string", () => {
        assert.deepStrictEqual(
          length(Type.bitstring("hello")),
          Type.integer(5),
        );
      });

      it("returns 1 for single character", () => {
        assert.deepStrictEqual(length(Type.bitstring("a")), Type.integer(1));
      });

      it("counts grapheme clusters, not codepoints", () => {
        // "e̊" is e (101) + combining ring above (778) = 1 grapheme cluster
        assert.deepStrictEqual(length(Type.bitstring("e̊")), Type.integer(1));
      });

      it("counts grapheme clusters in mixed string", () => {
        // "ß↑e̊" = 3 grapheme clusters (from Erlang docs)
        assert.deepStrictEqual(length(Type.bitstring("ß↑e̊")), Type.integer(3));
      });

      it("counts emoji as single grapheme cluster", () => {
        assert.deepStrictEqual(length(Type.bitstring("👋")), Type.integer(1));
      });

      it("counts string with multiple emoji", () => {
        assert.deepStrictEqual(
          length(Type.bitstring("Hello 👋 World 🌍")),
          Type.integer(15),
        );
      });

      it("handles multi-byte UTF-8 characters", () => {
        // Same as "ß↑e̊" in binary form (from Erlang docs)
        const binary = Bitstring.fromBytes([
          195, 159, 226, 134, 145, 101, 204, 138,
        ]);

        assert.deepStrictEqual(length(binary), Type.integer(3));
      });

      it("handles string with only combining characters after base", () => {
        // "a" + combining acute accent + combining ring above = 1 grapheme
        assert.deepStrictEqual(length(Type.bitstring("á̊")), Type.integer(1));
      });

      it("counts flag emoji as single grapheme cluster", () => {
        assert.deepStrictEqual(length(Type.bitstring("🇺🇸")), Type.integer(1));
      });

      it("counts ZWJ emoji sequence as single grapheme cluster", () => {
        assert.deepStrictEqual(length(Type.bitstring("👩‍💻")), Type.integer(1));
      });

      it("counts string with newlines and tabs", () => {
        assert.deepStrictEqual(
          length(Type.bitstring("a\nb\tc")),
          Type.integer(5),
        );
      });
    });

    describe("charlist input", () => {
      it("returns 0 for empty charlist", () => {
        assert.deepStrictEqual(length(Type.list()), Type.integer(0));
      });

      it("returns length of simple charlist", () => {
        assert.deepStrictEqual(length(Type.charlist("hello")), Type.integer(5));
      });

      it("counts grapheme clusters in charlist with combining characters", () => {
        // e (101) + combining ring above (778) = 1 grapheme cluster
        assert.deepStrictEqual(
          length(Type.list([Type.integer(101), Type.integer(778)])),
          Type.integer(1),
        );
      });
    });

    describe("mixed chardata input", () => {
      it("handles mixed chardata with binary in list", () => {
        assert.deepStrictEqual(
          length(Type.list([Type.bitstring("hello")])),
          Type.integer(5),
        );
      });

      it("handles mixed chardata with integers and binaries", () => {
        // [104, "ello"] = "hello" = 5
        assert.deepStrictEqual(
          length(Type.list([Type.integer(104), Type.bitstring("ello")])),
          Type.integer(5),
        );
      });

      it("handles nested list chardata", () => {
        assert.deepStrictEqual(
          length(
            Type.list([
              Type.list([Type.integer(104), Type.integer(101)]),
              Type.bitstring("llo"),
            ]),
          ),
          Type.integer(5),
        );
      });
    });

    describe("error cases", () => {
      it("raises FunctionClauseError for atom input", () => {
        assertBoxedError(
          () => length(Type.atom("atom")),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            Type.atom("atom"),
          ]),
        );
      });

      it("raises FunctionClauseError for integer input", () => {
        assertBoxedError(
          () => length(Type.integer(42)),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            Type.integer(42),
          ]),
        );
      });

      it("raises FunctionClauseError for non-binary bitstring", () => {
        const bitstring = Type.bitstring([1, 0, 1]);

        assertBoxedError(
          () => length(bitstring),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            bitstring,
          ]),
        );
      });

      it("raises FunctionClauseError for list with atom element", () => {
        assertBoxedError(
          () => length(Type.list([Type.atom("atom")])),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            Type.atom("atom"),
          ]),
        );
      });

      it("raises FunctionClauseError for list with non-binary bitstring", () => {
        const bitstring = Type.bitstring([1, 0, 1]);

        assertBoxedError(
          () => length(Type.list([bitstring])),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            bitstring,
          ]),
        );
      });

      it("raises FunctionClauseError for negative codepoint in list", () => {
        assertBoxedError(
          () => length(Type.list([Type.integer(-1)])),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            Type.integer(-1),
          ]),
        );
      });

      it("raises FunctionClauseError for very large codepoint in list", () => {
        assertBoxedError(
          () => length(Type.list([Type.integer(9_999_999)])),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            Type.integer(9_999_999),
          ]),
        );
      });

      it("raises FunctionClauseError for improper list", () => {
        assertBoxedError(
          () =>
            length(Type.improperList([Type.integer(104), Type.atom("tail")])),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            Type.atom("tail"),
          ]),
        );
      });

      it("raises ArgumentError for invalid bytes in binary", () => {
        assertBoxedError(
          () => length(Bitstring.fromBytes([255, 255])),
          "ArgumentError",
          "argument error: <<255, 255>>",
        );
      });
    });
  });

  describe("replace/3", () => {
    const replace3 = Erlang_String["replace/3"];
    const replace4 = Erlang_String["replace/4"];

    it("delegates to replace/4 with :leading direction", () => {
      // Use a string with multiple occurrences of the pattern to verify :leading (not :all or :trailing)
      const string = Type.bitstring("a-b-c");

      const pattern = Type.bitstring("-");
      const replacement = Type.bitstring("_");

      const result = replace3(string, pattern, replacement);

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.bitstring("a"),
          Type.bitstring("_"),
          Type.bitstring("b-c"),
        ]),
      );

      assert.deepStrictEqual(
        result,
        replace4(string, pattern, replacement, Type.atom("leading")),
      );
    });
  });

  describe("replace/4", () => {
    const replace = Erlang_String["replace/4"];
    const string = Type.bitstring("Hello World !");

    describe("direction variations", () => {
      it("with direction :all", () => {
        const result = replace(
          string,
          Type.bitstring(" "),
          Type.bitstring("_"),
          Type.atom("all"),
        );

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.bitstring("Hello"),
            Type.bitstring("_"),
            Type.bitstring("World"),
            Type.bitstring("_"),
            Type.bitstring("!"),
          ]),
        );
      });

      it("with direction :leading", () => {
        const result = replace(
          string,
          Type.bitstring(" "),
          Type.bitstring("_"),
          Type.atom("leading"),
        );

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.bitstring("Hello"),
            Type.bitstring("_"),
            Type.bitstring("World !"),
          ]),
        );
      });

      it("with direction :trailing", () => {
        const result = replace(
          string,
          Type.bitstring(" "),
          Type.bitstring("_"),
          Type.atom("trailing"),
        );

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.bitstring("Hello World"),
            Type.bitstring("_"),
            Type.bitstring("!"),
          ]),
        );
      });
    });

    describe("pattern position edge cases", () => {
      it("when pattern is at the start of the string", () => {
        const result = replace(
          Type.bitstring("Hello"),
          Type.bitstring("He"),
          Type.bitstring("A"),
          Type.atom("leading"),
        );

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.bitstring(""),
            Type.bitstring("A"),
            Type.bitstring("llo"),
          ]),
        );
      });

      it("when pattern is at the end of the string", () => {
        const result = replace(
          Type.bitstring("Hello"),
          Type.bitstring("lo"),
          Type.bitstring("p"),
          Type.atom("trailing"),
        );

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.bitstring("Hel"),
            Type.bitstring("p"),
            Type.bitstring(""),
          ]),
        );
      });

      it("with consecutive patterns", () => {
        const result = replace(
          Type.bitstring("lololo"),
          Type.bitstring("lo"),
          Type.bitstring("ha"),
          Type.atom("all"),
        );

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.bitstring(""),
            Type.bitstring("ha"),
            Type.bitstring(""),
            Type.bitstring("ha"),
            Type.bitstring(""),
            Type.bitstring("ha"),
            Type.bitstring(""),
          ]),
        );
      });
    });

    describe("input edge cases", () => {
      it("with empty pattern", () => {
        const result = replace(
          string,
          Type.bitstring(""),
          Type.bitstring("_"),
          Type.atom("all"),
        );

        assert.deepStrictEqual(result, Type.list([string]));
      });

      it("when pattern is not found", () => {
        const result = replace(
          string,
          Type.bitstring("."),
          Type.bitstring("_"),
          Type.atom("all"),
        );

        assert.deepStrictEqual(result, Type.list([string]));
      });

      it("with empty replacement", () => {
        const result = replace(
          Type.bitstring("Hello World"),
          Type.bitstring(" "),
          Type.bitstring(""),
          Type.atom("all"),
        );

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.bitstring("Hello"),
            Type.bitstring(""),
            Type.bitstring("World"),
          ]),
        );
      });

      it("with unicode pattern", () => {
        const result = replace(
          Type.bitstring("Hello 👋 World"),
          Type.bitstring("👋"),
          Type.bitstring("🌍"),
          Type.atom("all"),
        );

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.bitstring("Hello "),
            Type.bitstring("🌍"),
            Type.bitstring(" World"),
          ]),
        );
      });
    });

    describe("replacement type variations", () => {
      it("accepts atom as replacement and inserts it as-is", () => {
        const result = replace(
          string,
          Type.bitstring(" "),
          Type.atom("_"),
          Type.atom("all"),
        );

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.bitstring("Hello"),
            Type.atom("_"),
            Type.bitstring("World"),
            Type.atom("_"),
            Type.bitstring("!"),
          ]),
        );
      });

      it("accepts charlist as replacement and inserts it as-is", () => {
        const result = replace(
          string,
          Type.bitstring(" "),
          Type.charlist("_"),
          Type.atom("all"),
        );

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.bitstring("Hello"),
            Type.charlist("_"),
            Type.bitstring("World"),
            Type.charlist("_"),
            Type.bitstring("!"),
          ]),
        );
      });
    });

    describe("error cases", () => {
      it("raises MatchError if the first argument is not valid chardata", () => {
        const invalidArg = Type.atom("hello_world");

        assertBoxedError(
          () =>
            replace(
              invalidArg,
              Type.bitstring("_"),
              Type.bitstring(" "),
              Type.atom("all"),
            ),
          "MatchError",
          Interpreter.buildMatchErrorMsg(invalidArg),
        );
      });

      it("raises ArgumentError if the second argument is not valid chardata", () => {
        assertBoxedError(
          () =>
            replace(
              Type.bitstring("Hello_World_!"),
              Type.atom("_"),
              Type.bitstring(" "),
              Type.atom("all"),
            ),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(
            1,
            "not valid character data (an iodata term)",
          ),
        );
      });

      it("raises CaseClauseError if the fourth argument is not an atom", () => {
        assertBoxedError(
          () =>
            replace(
              Type.bitstring("Hello World !"),
              Type.bitstring(" "),
              Type.bitstring("_"),
              Type.bitstring("all"),
            ),
          "CaseClauseError",
          'no case clause matching: "all"',
        );
      });

      it("raises CaseClauseError if the fourth argument is an unrecognized atom", () => {
        assertBoxedError(
          () =>
            replace(
              Type.bitstring("Hello World"),
              Type.bitstring(" "),
              Type.bitstring("_"),
              Type.atom("invalid"),
            ),
          "CaseClauseError",
          "no case clause matching: :invalid",
        );
      });
    });
  });

  describe("split/2", () => {
    const testedFun = Erlang_String["split/2"];

    it("delegates to split/3 with :leading direction", () => {
      const subject = Type.bitstring("a-b-c");
      const pattern = Type.bitstring("-");

      assert.deepStrictEqual(
        testedFun(subject, pattern),
        Erlang_String["split/3"](subject, pattern, Type.atom("leading")),
      );
    });
  });

  describe("split/3", () => {
    const split = Erlang_String["split/3"];
    const subject = Type.bitstring("Hello World !");

    it("with empty pattern", () => {
      const result = split(subject, Type.bitstring(""), Type.atom("all"));

      assert.deepStrictEqual(result, Type.list([Bitstring.toText(subject)]));
    });

    it("with pattern not found in subject", () => {
      const result = split(subject, Type.bitstring("."), Type.atom("all"));

      assert.deepStrictEqual(result, Type.list([Bitstring.toText(subject)]));
    });

    it("with direction :all", () => {
      const result = split(subject, Type.bitstring(" "), Type.atom("all"));

      assert.deepStrictEqual(result, Type.list(["Hello", "World", "!"]));
    });

    it("with direction :leading", () => {
      const result = split(subject, Type.bitstring(" "), Type.atom("leading"));

      assert.deepStrictEqual(result, Type.list(["Hello", "World !"]));
    });

    it("with direction :trailing", () => {
      const result = split(subject, Type.bitstring(" "), Type.atom("trailing"));

      assert.deepStrictEqual(result, Type.list(["Hello World", "!"]));
    });

    it("with pattern at the start of the subject", () => {
      const result = split(subject, Type.bitstring("H"), Type.atom("leading"));

      assert.deepStrictEqual(result, Type.list(["", "ello World !"]));
    });

    it("with pattern at the end of the subject", () => {
      const result = split(subject, Type.bitstring("!"), Type.atom("trailing"));

      assert.deepStrictEqual(result, Type.list(["Hello World ", ""]));
    });

    it("with consecutive pattern", () => {
      const result = split(subject, Type.bitstring("l"), Type.atom("all"));

      assert.deepStrictEqual(result, Type.list(["He", "", "o Wor", "d !"]));
    });

    it("with unicode pattern", () => {
      const result = split(
        Type.bitstring("Hello 👋 World"),
        Type.bitstring("👋"),
        Type.atom("all"),
      );

      assert.deepStrictEqual(result, Type.list(["Hello ", " World"]));
    });

    it("with charlist subject and charlist pattern", () => {
      const result = split(
        Type.charlist("Hello World"),
        Type.charlist(" "),
        Type.atom("all"),
      );

      assert.deepStrictEqual(
        result,
        Type.list([Type.charlist("Hello"), Type.charlist("World")]),
      );
    });

    it("with charlist subject and binary pattern", () => {
      const result = split(
        Type.charlist("Hello World"),
        Type.bitstring(" "),
        Type.atom("all"),
      );

      assert.deepStrictEqual(
        result,
        Type.list([Type.charlist("Hello"), Type.charlist("World")]),
      );
    });

    it("with binary subject and charlist pattern", () => {
      const result = split(
        Type.bitstring("Hello World"),
        Type.charlist(" "),
        Type.atom("all"),
      );

      assert.deepStrictEqual(result, Type.list(["Hello", "World"]));
    });

    it("raises MatchError if the first argument is not valid chardata", () => {
      assertBoxedError(
        () =>
          split(
            Type.atom("hello_world"),
            Type.bitstring("_"),
            Type.atom("all"),
          ),
        "MatchError",
        Interpreter.buildMatchErrorMsg(Type.atom("hello_world")),
      );
    });

    it("raises MatchError if the first argument is a non-binary bitstring", () => {
      const nonBinaryBitstring = Type.bitstring([1, 0, 1]);

      assertBoxedError(
        () => split(nonBinaryBitstring, Type.bitstring(" "), Type.atom("all")),
        "MatchError",
        Interpreter.buildMatchErrorMsg(nonBinaryBitstring),
      );
    });

    it("raises ArgumentError if the second argument is not valid chardata", () => {
      assertBoxedError(
        () =>
          split(
            Type.bitstring("Hello_World_!"),
            Type.atom("_"),
            Type.atom("all"),
          ),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises ArgumentError if the second argument is a non-binary bitstring", () => {
      assertBoxedError(
        () =>
          split(
            Type.bitstring("Hello World"),
            Type.bitstring([1, 0, 1]),
            Type.atom("all"),
          ),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    });

    it("raises CaseClauseError if the third argument is not an atom", () => {
      assertBoxedError(
        () =>
          split(
            Type.bitstring("Hello World !"),
            Type.bitstring(" "),
            Type.bitstring("all"),
          ),
        "CaseClauseError",
        'no case clause matching: "all"',
      );
    });

    it("raises CaseClauseError if the third argument is an unrecognized atom", () => {
      assertBoxedError(
        () =>
          split(
            Type.bitstring("hello world"),
            Type.bitstring(" "),
            Type.atom("invalid"),
          ),
        "CaseClauseError",
        "no case clause matching: :invalid",
      );
    });
  });

  describe("titlecase/1", () => {
    const titlecase = Erlang_String["titlecase/1"];

    describe("with binary input", () => {
      it("returns empty binary for empty string", () => {
        const input = Type.bitstring("");
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.bitstring(""));
      });

      it("uppercases first character of ASCII string", () => {
        const input = Type.bitstring("hello");
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.bitstring("Hello"));
      });

      it("handles already uppercase first character", () => {
        const input = Type.bitstring("Hello");
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.bitstring("Hello"));
      });

      it("handles single lowercase character", () => {
        const input = Type.bitstring("a");
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.bitstring("A"));
      });

      it("handles single uppercase character", () => {
        const input = Type.bitstring("Z");
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.bitstring("Z"));
      });

      it("uses custom mapping for German ß (223 → [83, 115] = 'Ss')", () => {
        const input = Type.bitstring("ßtest");
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.bitstring("Sstest"));
      });

      it("uses range check for Georgian character (codepoint 4304)", () => {
        const input = Type.bitstring(String.fromCodePoint(4304) + "test");
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.bitstring(String.fromCodePoint(4304) + "test"),
        );
      });

      it("uses range check for Greek character (codepoint 8072)", () => {
        const input = Type.bitstring(String.fromCodePoint(8072) + "test");
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.bitstring(String.fromCodePoint(8072) + "test"),
        );
      });

      it("uses range check for Greek character (codepoint 8088)", () => {
        const input = Type.bitstring(String.fromCodePoint(8088));
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.bitstring(String.fromCodePoint(8088)),
        );
      });

      it("uses range check for Greek character (codepoint 8104)", () => {
        const input = Type.bitstring(String.fromCodePoint(8104));
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.bitstring(String.fromCodePoint(8104)),
        );
      });

      it("uses range check for Greek character (codepoint 8111)", () => {
        const input = Type.bitstring(String.fromCodePoint(8111) + "end");
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.bitstring(String.fromCodePoint(8111) + "end"),
        );
      });

      it("uses range check for character (codepoint 68976)", () => {
        const input = Type.bitstring(String.fromCodePoint(68_976));
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.bitstring(String.fromCodePoint(68_976)),
        );
      });

      it("uses custom mapping from MAPPING object (452 → 453)", () => {
        const input = Type.bitstring(String.fromCodePoint(452) + "test");
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.bitstring(String.fromCodePoint(453) + "test"),
        );
      });

      it("uses custom mapping for ligature ﬁ (64257 → [70, 105] = 'Fi')", () => {
        const input = Type.bitstring(String.fromCodePoint(64_257) + "re");
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.bitstring("Fire"));
      });

      it("uses custom mapping that expands to multiple codepoints (8114 → [8122, 837])", () => {
        const input = Type.bitstring(String.fromCodePoint(8114) + "x");
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.bitstring(String.fromCodePoint(8122, 837) + "x"),
        );
      });

      it("uses custom mapping for ligature ﬃ (64259 → [70, 102, 105] = 'Ffi')", () => {
        const input = Type.bitstring(String.fromCodePoint(64259));
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.bitstring("Ffi"));
      });

      it("titlecases word without special case rules", () => {
        const input = Type.bitstring("world");
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.bitstring("World"));
      });

      it("raises ArgumentError for invalid UTF-8 binary", () => {
        const invalidBinary = Bitstring.fromBytes([255, 255]);

        assertBoxedError(
          () => titlecase(invalidBinary),
          "ArgumentError",
          "argument error: <<255, 255>>",
        );
      });

      it("raises ArgumentError for surrogate pair codepoint", () => {
        // Create a binary with surrogate pair codepoint (0xD800 in UTF-8: ED A0 80)
        const invalidBinary = Bitstring.fromBytes([0xed, 0xa0, 0x80]);

        assertBoxedError(
          () => titlecase(invalidBinary),
          "ArgumentError",
          "argument error: <<237, 160, 128>>",
        );
      });
    });

    describe("with list of integers (charlist)", () => {
      it("returns empty list for empty list", () => {
        const input = Type.list();
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.list());
      });

      it("uppercases first codepoint in charlist", () => {
        const input = Type.list([
          Type.integer(97),
          Type.integer(98),
          Type.integer(99),
        ]); // "abc"

        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(65), Type.integer(98), Type.integer(99)]),
        ); // "Abc"
      });

      it("handles already uppercase first codepoint", () => {
        const input = Type.list([Type.integer(72), Type.integer(105)]); // "Hi"
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(72), Type.integer(105)]),
        );
      });

      it("handles single lowercase codepoint", () => {
        const input = Type.list([Type.integer(122)]); // "z"
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(90)])); // "Z"
      });

      it("expands first codepoint to multiple codepoints (ß = 223 → [83, 115])", () => {
        const input = Type.list([Type.integer(223), Type.integer(97)]); // "ßa"
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(83), Type.integer(115), Type.integer(97)]),
        ); // "Ssa"
      });

      it("expands first codepoint to three codepoints (64259 → [70, 102, 105])", () => {
        const input = Type.list([Type.integer(64_259), Type.integer(120)]); // "ﬃx"
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(70),
            Type.integer(102),
            Type.integer(105),
            Type.integer(120),
          ]),
        ); // "Ffix"
      });

      it("uses range check for codepoint 4304", () => {
        const input = Type.list([Type.integer(4304), Type.integer(97)]);
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(4304), Type.integer(97)]),
        );
      });

      it("uses custom mapping for codepoint 452", () => {
        const input = Type.list([Type.integer(452), Type.integer(97)]);
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(453), Type.integer(97)]),
        );
      });

      it("uses custom mapping that expands for codepoint 8114", () => {
        const input = Type.list([Type.integer(8114), Type.integer(120)]);
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(8122), Type.integer(837), Type.integer(120)]),
        );
      });

      it("titlecases codepoint without special case rules", () => {
        const input = Type.list([Type.integer(119)]); // "w"
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(87)])); // "W"
      });

      it("does not validate surrogate pair codepoint in charlist", () => {
        // Erlang does not validate surrogate pairs in charlists
        const input = Type.list([Type.integer(55_296)]);
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(55_296)]));
      });
    });

    describe("with list starting with binary", () => {
      it("processes single character binary", () => {
        const input = Type.list([Type.bitstring("a"), Type.integer(98)]);
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(65), Type.bitstring(""), Type.integer(98)]),
        );
      });

      it("processes multi-character binary", () => {
        const input = Type.list([Type.bitstring("hello"), Type.integer(97)]);
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(72),
            Type.bitstring("ello"),
            Type.integer(97),
          ]),
        );
      });

      it("processes binary alone in list", () => {
        const input = Type.list([Type.bitstring("test")]);
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(84), Type.bitstring("est")]),
        );
      });

      it("expands binary first char to multiple codepoints (ß)", () => {
        const input = Type.list([Type.bitstring("ßx"), Type.integer(97)]);
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(83),
            Type.integer(115),
            Type.bitstring("x"),
            Type.integer(97),
          ]),
        );
      });

      it("expands ligature ﬁ (64257) to nested list when binary has trailing content", () => {
        const segments = [
          Type.bitstringSegment(Type.integer(64_257), {type: "utf8"}),
          Type.bitstringSegment(Type.bitstring("le"), {type: "bitstring"}),
        ];

        const input = Type.list([Bitstring.fromSegments(segments)]);
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.list([Type.integer(70), Type.integer(105)]),
            Type.bitstring("le"),
          ]),
        );
      });

      it("expands ligature ﬁ (64257) to flat list when followed by separate binary", () => {
        const input = Type.list([
          Type.bitstring(String.fromCodePoint(64_257)),
          Type.bitstring("ox"),
        ]);

        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(70),
            Type.integer(105),
            Type.bitstring(""),
            Type.bitstring("ox"),
          ]),
        );
      });

      it("expands ligature ﬁ (64257) to flat list when alone in list", () => {
        const input = Type.list([Type.bitstring(String.fromCodePoint(64_257))]);

        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(70), Type.integer(105)]),
        );
      });

      it("expands ligature ﬁ (64257) to flat list when followed by separate empty binary", () => {
        const input = Type.list([
          Type.bitstring(String.fromCodePoint(64_257)),
          Type.bitstring(""),
        ]);

        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(70),
            Type.integer(105),
            Type.bitstring(""),
            Type.bitstring(""),
          ]),
        );
      });

      it("expands ligature ﬁ (64257) to flat list when followed by separate integer", () => {
        const input = Type.list([
          Type.bitstring(String.fromCodePoint(64_257)),
          Type.integer(97),
        ]);

        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(70),
            Type.integer(105),
            Type.bitstring(""),
            Type.integer(97),
          ]),
        );
      });

      it("expands ligature ﬀ (64256) to nested list when binary has trailing content", () => {
        const segments = [
          Type.bitstringSegment(Type.integer(64_256), {type: "utf8"}),
          Type.bitstringSegment(Type.bitstring("ox"), {type: "bitstring"}),
        ];

        const input = Type.list([Bitstring.fromSegments(segments)]);

        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.list([Type.integer(70), Type.integer(102)]),
            Type.bitstring("ox"),
          ]),
        );
      });

      it("expands ligature ﬀ (64256) to flat list when followed by separate binary", () => {
        const input = Type.list([
          Type.bitstring(String.fromCodePoint(64_256)),
          Type.bitstring("ox"),
        ]);

        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(70),
            Type.integer(102),
            Type.bitstring(""),
            Type.bitstring("ox"),
          ]),
        );
      });

      it("expands ligature ﬄ (64260) to nested list when binary has trailing content", () => {
        const segments = [
          Type.bitstringSegment(Type.integer(64_260), {type: "utf8"}),
          Type.bitstringSegment(Type.bitstring("at"), {type: "bitstring"}),
        ];

        const input = Type.list([Bitstring.fromSegments(segments)]);
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.list([Type.integer(70), Type.integer(102), Type.integer(108)]),
            Type.bitstring("at"),
          ]),
        );
      });

      it("expands ligature ﬄ (64260) to flat list when followed by separate binary", () => {
        const input = Type.list([
          Type.bitstring(String.fromCodePoint(64_260)),
          Type.bitstring("at"),
        ]);

        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(70),
            Type.integer(102),
            Type.integer(108),
            Type.bitstring(""),
            Type.bitstring("at"),
          ]),
        );
      });

      it("raises ArgumentError for invalid UTF-8 binary in list", () => {
        const invalidBinary = Bitstring.fromBytes([255, 255]);
        const input = Type.list([invalidBinary]);

        assertBoxedError(
          () => titlecase(input),
          "ArgumentError",
          "argument error: <<255, 255>>",
        );
      });

      it("returns empty list for empty binary in list", () => {
        const input = Type.list([Type.bitstring("")]);
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.list());
      });
    });

    describe("with nested list", () => {
      it("processes nested list with single integer, rest is single integer", () => {
        const input = Type.list([
          Type.list([Type.integer(97)]),
          Type.integer(98),
        ]);

        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(65), Type.integer(98)]),
        );
      });

      it("processes nested list with multiple integers, rest is multiple integers", () => {
        const input = Type.list([
          Type.list([Type.integer(104), Type.integer(101)]), // "he"
          Type.integer(108),
          Type.integer(108),
        ]); // "ll"

        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(72),
            Type.integer(101),
            Type.integer(108),
            Type.integer(108),
          ]),
        ); // "Hell"
      });

      it("processes nested list where rest starts with binary", () => {
        const input = Type.list([
          Type.list([Type.integer(97)]),
          Type.bitstring("test"),
          Type.integer(99),
        ]);

        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(65),
            Type.bitstring("test"),
            Type.integer(99),
          ]),
        );
      });

      it("processes nested list where rest starts with binary, no remainder", () => {
        const input = Type.list([
          Type.list([Type.integer(97)]),
          Type.bitstring("test"),
        ]);

        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(65), Type.bitstring("test")]),
        );
      });

      it("processes nested list with binary inside, multiple rest elements", () => {
        const input = Type.list([
          Type.list([Type.bitstring("ab")]),
          Type.integer(99),
          Type.integer(100),
        ]);

        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(65),
            Type.bitstring("b"),
            Type.integer(99),
            Type.integer(100),
          ]),
        );
      });

      it("processes nested list with binary inside, single rest element", () => {
        const input = Type.list([
          Type.list([Type.bitstring("ab")]),
          Type.integer(99),
        ]);

        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(65), Type.bitstring("b"), Type.integer(99)]),
        );
      });

      it("processes nested list with no rest", () => {
        const input = Type.list([Type.list([Type.integer(120)])]);
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(88)]));
      });

      it("processes deeply nested list", () => {
        const input = Type.list([Type.list([Type.list([Type.integer(97)])])]);
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(65)]));
      });

      it("processes nested list with binary that expands", () => {
        const input = Type.list([Type.list([Type.bitstring("ß")])]);
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(83), Type.integer(115)]),
        );
      });

      it("processes nested list with integer that expands", () => {
        const input = Type.list([
          Type.list([Type.integer(223)]),
          Type.integer(97),
        ]);

        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(83), Type.integer(115), Type.integer(97)]),
        );
      });
    });

    describe("edge cases", () => {
      it("returns empty list for empty nested list", () => {
        const input = Type.list([Type.list()]);
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.list());
      });

      it("returns zero codepoint as-is", () => {
        const input = Type.list([Type.integer(0)]);
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(0)]));
      });

      it("returns large codepoint outside BMP as-is", () => {
        const input = Type.list([Type.integer(128_512)]); // 😀 emoji
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(128_512)]));
      });

      it("handles multiple empty binaries in list", () => {
        const input = Type.list([
          Type.bitstring(""),
          Type.bitstring(""),
          Type.integer(97),
        ]);

        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(65)]));
      });

      it("handles nested list with empty binary", () => {
        const input = Type.list([
          Type.list([Type.bitstring("")]),
          Type.integer(97),
        ]);

        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(65)]));
      });

      it("raises FunctionClauseError for negative integer", () => {
        const input = Type.list([Type.integer(-1)]);

        assertBoxedError(
          () => titlecase(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            Type.integer(-1),
          ]),
        );
      });

      it("raises FunctionClauseError for very large integer", () => {
        const input = Type.list([Type.integer(9_999_999)]);

        assertBoxedError(
          () => titlecase(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            Type.integer(9_999_999),
          ]),
        );
      });

      it("raises FunctionClauseError for non-byte-aligned bitstring", () => {
        const bitstring = Type.bitstring([1, 0, 1]);

        assertBoxedError(
          () => titlecase(bitstring),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":string.titlecase/1", [
            bitstring,
          ]),
        );
      });

      it("raises FunctionClauseError for list with non-byte-aligned bitstring", () => {
        const bitstring = Type.bitstring([1, 0, 1]);
        const input = Type.list([bitstring]);

        assertBoxedError(
          () => titlecase(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            bitstring,
          ]),
        );
      });
    });

    describe("error handling", () => {
      it("raises FunctionClauseError for integer input", () => {
        const input = Type.integer(42);

        assertBoxedError(
          () => titlecase(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":string.titlecase/1", [
            input,
          ]),
        );
      });

      it("raises FunctionClauseError for atom input", () => {
        const input = Type.atom("test");

        assertBoxedError(
          () => titlecase(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":string.titlecase/1", [
            input,
          ]),
        );
      });

      it("raises FunctionClauseError for float input", () => {
        const input = Type.float(3.14);

        assertBoxedError(
          () => titlecase(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":string.titlecase/1", [
            input,
          ]),
        );
      });

      it("raises FunctionClauseError for list with atom first element", () => {
        const input = Type.list([Type.atom("invalid")]);

        assertBoxedError(
          () => titlecase(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            Type.atom("invalid"),
          ]),
        );
      });

      it("raises FunctionClauseError for list with float first element", () => {
        const input = Type.list([Type.float(3.14)]);

        assertBoxedError(
          () => titlecase(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            Type.float(3.14),
          ]),
        );
      });
    });
  });
});
