"use strict";

import {
  assert,
  assertBoxedError,
  defineRuntimeGlobals,
} from "../../support/helpers.mjs";

import Elixir_String_Tokenizer from "../../../../assets/js/elixir/string/tokenizer.mjs";
import Interpreter from "../../../../assets/js/interpreter.mjs";
import Type from "../../../../assets/js/type.mjs";

defineRuntimeGlobals();

// Mirrors the clause heads the compiler emits for the ported function, which
// the runtime script registers when the bundle loads.
Interpreter.defineFunctionClauseHeads(
  "String.Tokenizer",
  "tokenize",
  1,
  "public",
  [
    {
      params: (_context) => [
        Type.consPattern(
          Type.variablePattern("head_0"),
          Type.variablePattern("tail_1"),
        ),
      ],
      guards: [],
      blame: {params: ["[head | tail]"], guards: []},
    },
    {
      params: (_context) => [Type.list()],
      guards: [],
      blame: {params: ["[]"], guards: []},
    },
  ],
);

const tokenize = (codePoints) =>
  Elixir_String_Tokenizer["tokenize/1"](
    Type.list(codePoints.map((codePoint) => Type.integer(codePoint))),
  );

const codePoints = (text) => Array.from(text).map((c) => c.codePointAt(0));

const charlist = (text) => Type.list(codePoints(text).map(Type.integer));

const success = (kind, acc, rest, length, asciiLetters, special) =>
  Type.tuple([
    Type.atom(kind),
    charlist(acc),
    charlist(rest),
    Type.integer(length),
    Type.boolean(asciiLetters),
    Type.list(special.map(Type.atom)),
  ]);

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/elixir/string/tokenizer_test.exs
// Always update both together.

describe("Elixir_String_Tokenizer", () => {
  describe("tokenize/1", () => {
    it("lowercase identifier", () => {
      assert.deepStrictEqual(
        tokenize(codePoints("foo")),
        success("identifier", "foo", "", 3, true, []),
      );
    });

    it("identifier with underscore and digits", () => {
      assert.deepStrictEqual(
        tokenize(codePoints("foo_bar1")),
        success("identifier", "foo_bar1", "", 8, true, []),
      );
    });

    it("identifier starting with underscore", () => {
      assert.deepStrictEqual(
        tokenize(codePoints("_foo")),
        success("identifier", "_foo", "", 4, true, []),
      );
    });

    it("identifier closed by punctuation", () => {
      assert.deepStrictEqual(
        tokenize(codePoints("foo?")),
        success("identifier", "foo?", "", 4, true, ["punctuation"]),
      );
    });

    it("punctuation closes the identifier before the rest", () => {
      assert.deepStrictEqual(
        tokenize(codePoints("foo??")),
        success("identifier", "foo?", "?", 4, true, ["punctuation"]),
      );
    });

    it("identifier carrying the at sign", () => {
      assert.deepStrictEqual(
        tokenize(codePoints("foo@bar")),
        success("identifier", "foo@bar", "", 7, true, ["at"]),
      );
    });

    it("alias", () => {
      assert.deepStrictEqual(
        tokenize(codePoints("FooBar")),
        success("alias", "FooBar", "", 6, true, []),
      );
    });

    it("alias stops at the dot", () => {
      assert.deepStrictEqual(
        tokenize(codePoints("Elixir.Foo")),
        success("alias", "Elixir", ".Foo", 6, true, []),
      );
    });

    it("identifier stops at an ASCII non-identifier character", () => {
      assert.deepStrictEqual(
        tokenize(codePoints("foo bar")),
        success("identifier", "foo", " bar", 3, true, []),
      );
    });

    it("Unicode identifier", () => {
      assert.deepStrictEqual(
        tokenize(codePoints("héllo")),
        success("identifier", "héllo", "", 5, false, []),
      );
    });

    it("Han identifier", () => {
      assert.deepStrictEqual(
        tokenize(codePoints("日本語")),
        success("identifier", "日本語", "", 3, false, []),
      );
    });

    it("uppercase non-ASCII starts an atom", () => {
      assert.deepStrictEqual(
        tokenize(codePoints("Ω")),
        success("atom", "Ω", "", 1, false, []),
      );
    });

    it("NFC-normalizes and flags an unstable identifier", () => {
      // e followed by combining acute normalizes to é
      assert.deepStrictEqual(
        tokenize([101, 769]),
        success("identifier", "é", "", 2, false, ["nfkc"]),
      );
    });

    it("Greek mu combines with any script", () => {
      assert.deepStrictEqual(
        tokenize(codePoints("aμ")),
        success("identifier", "aμ", "", 2, false, []),
      );
    });

    it("underscore separates chunks checked for scripts on their own", () => {
      assert.deepStrictEqual(
        tokenize(codePoints("fox_狐")),
        success("identifier", "fox_狐", "", 5, false, []),
      );
    });

    it("empty input", () => {
      assert.deepStrictEqual(
        tokenize([]),
        Type.tuple([Type.atom("error"), Type.atom("empty")]),
      );
    });

    it("digit can't start an identifier", () => {
      assert.deepStrictEqual(
        tokenize(codePoints("1abc")),
        Type.tuple([Type.atom("error"), Type.atom("empty")]),
      );
    });

    it("at sign can't start an identifier", () => {
      assert.deepStrictEqual(
        tokenize(codePoints("@foo")),
        Type.tuple([Type.atom("error"), Type.atom("empty")]),
      );
    });

    it("restricted codepoint can't start an identifier", () => {
      // fullwidth f is excluded by UTS 39
      assert.deepStrictEqual(
        tokenize(codePoints("ｆｏｏ")),
        Type.tuple([Type.atom("error"), Type.atom("empty")]),
      );
    });

    it("restricted codepoint inside an identifier is unexpected", () => {
      // superscript two is excluded by UTS 39
      assert.deepStrictEqual(
        tokenize(codePoints("x²")),
        Type.tuple([
          Type.atom("error"),
          Type.tuple([Type.atom("unexpected_token"), charlist("x²")]),
        ]),
      );
    });

    it("mixed scripts are rejected", () => {
      const result = tokenize(codePoints("a日"));
      const [tag, reason] = result.data;

      assert.deepStrictEqual(tag, Type.atom("error"));

      const [reasonTag, acc, message] = reason.data;

      assert.deepStrictEqual(reasonTag, Type.atom("mixed_script"));
      assert.deepStrictEqual(acc, charlist("a日"));

      // The prefix matches the server. The suffix explanation is simplified - it lists the
      // characters without their script names (see the module comment).
      assert.deepStrictEqual(
        message.data[0],
        charlist("invalid mixed-script identifier found: "),
      );

      assert.isTrue(Type.isList(message.data[1]));
    });

    it("raises FunctionClauseError if the argument is not a list", () => {
      assertBoxedError(
        () => Elixir_String_Tokenizer["tokenize/1"](Type.atom("abc")),
        "FunctionClauseError",
        "no function clause matching in String.Tokenizer.tokenize/1\n\nThe following arguments were given to String.Tokenizer.tokenize/1:\n\n    # 1\n    :abc\n\nAttempted function clauses (showing 2 out of 2):\n\n    def tokenize(-[head | tail]-)\n    def tokenize(-[]-)\n",
      );
    });
  });
});
