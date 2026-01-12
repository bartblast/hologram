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
        const input = Type.bitstring(String.fromCodePoint(68976));
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.bitstring(String.fromCodePoint(68976)),
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
        const input = Type.bitstring(String.fromCodePoint(64257) + "re");
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

      it("uses JavaScript toUpperCase for regular character", () => {
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
        const input = Type.list([Type.integer(64259), Type.integer(120)]); // "ﬃx"
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

      it("uses JavaScript toUpperCase for regular codepoint", () => {
        const input = Type.list([Type.integer(119)]); // "w"
        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(87)])); // "W"
      });

      it("raises ArgumentError for surrogate pair codepoint", () => {
        const input = Type.list([Type.integer(55296)]);

        assertBoxedError(
          () => titlecase(input),
          "ArgumentError",
          "argument error: [55296]",
        );
      });
    });

    describe("with list starting with binary", () => {
      it("processes single character binary", () => {
        const input = Type.list([Type.bitstring("a"), Type.integer(98)]);
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(65), Type.integer(98)]),
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

      it("expands binary first char with ligature ﬁ (64257)", () => {
        const input = Type.list([
          Type.bitstring(String.fromCodePoint(64257) + "le"),
        ]);
        const result = titlecase(input);

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.integer(70),
            Type.integer(105),
            Type.bitstring("le"),
          ]),
        );
      });

      it("raises ArgumentError for invalid UTF-8 binary in list", () => {
        const invalidBinary = Bitstring.fromBytes([255, 255]);
        const input = Type.list([invalidBinary]);

        assertBoxedError(
          () => titlecase(input),
          "ArgumentError",
          "argument error: [<<255, 255>>]",
        );
      });

      it("raises FunctionClauseError for empty binary in list", () => {
        const input = Type.list([Type.bitstring("")]);

        assertBoxedError(
          () => titlecase(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            input,
          ]),
        );
      });
    });

    describe("with nested list", () => {
      it("processes nested list with only integers, rest only integers (Rule 1)", () => {
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

      it("processes nested list with multiple integers, rest with integers (Rule 1)", () => {
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

      it("processes nested list where rest starts with binary (Rule 2)", () => {
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
            Type.list([Type.integer(99)]),
          ]),
        );
      });

      it("processes nested list where rest starts with binary, no remainder (Rule 2)", () => {
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

      it("processes nested list with binary inside, multiple rest elements (Rule 3)", () => {
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
            Type.list([Type.integer(99), Type.integer(100)]),
          ]),
        );
      });

      it("processes nested list with binary inside, single rest element (Rule 4)", () => {
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

      it("processes triple nested list", () => {
        const input = Type.list([
          Type.list([Type.list([Type.list([Type.integer(122)])])]),
        ]);

        const result = titlecase(input);

        assert.deepStrictEqual(result, Type.list([Type.integer(90)]));
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
          Interpreter.buildFunctionClauseErrorMsg(":string.titlecase/1", [
            input,
          ]),
        );
      });

      it("raises FunctionClauseError for list with float first element", () => {
        const input = Type.list([Type.float(3.14)]);

        assertBoxedError(
          () => titlecase(input),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":string.titlecase/1", [
            input,
          ]),
        );
      });
    });
  });
});
