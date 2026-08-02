"use strict";

import {assert, defineRuntimeGlobals} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Elixir_FunctionClauseError from "../../../assets/js/elixir/function_clause_error.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

const message = (struct) =>
  Bitstring.toText(Elixir_FunctionClauseError["message/1"](struct));

function blamedNode(match, source) {
  return Type.map([
    [Type.atom("match?"), Type.boolean(match)],
    [Type.atom("source"), Type.bitstring(source)],
  ]);
}

function structFixture(data = {}) {
  const {args, clauses, kind} = data;

  return Type.struct("FunctionClauseError", [
    [Type.atom("__exception__"), Type.boolean(true)],
    [Type.atom("args"), args ?? Type.nil()],
    [Type.atom("arity"), Type.integer(2)],
    [Type.atom("clauses"), clauses ?? Type.nil()],
    [Type.atom("function"), Type.atom("my_fun")],
    [Type.atom("kind"), kind ?? Type.nil()],
    [Type.atom("module"), Type.alias("MyModule")],
  ]);
}

describe("Elixir_FunctionClauseError", () => {
  describe("message/1", () => {
    it("returns the eager message when the struct carries one", () => {
      const struct = Type.errorStruct("FunctionClauseError", "my message");

      assert.equal(message(struct), "my message");
    });

    it("names no function when the struct has none", () => {
      const struct = Type.struct("FunctionClauseError", [
        [Type.atom("__exception__"), Type.boolean(true)],
        [Type.atom("args"), Type.nil()],
        [Type.atom("arity"), Type.nil()],
        [Type.atom("clauses"), Type.nil()],
        [Type.atom("function"), Type.nil()],
        [Type.atom("kind"), Type.nil()],
        [Type.atom("module"), Type.nil()],
      ]);

      assert.equal(message(struct), "no function clause matches");
    });

    it("names the function when the args are not known", () => {
      assert.equal(
        message(structFixture()),
        "no function clause matching in MyModule.my_fun/2",
      );
    });

    it("quotes a function name that doesn't read as an identifier", () => {
      const struct = Type.struct("FunctionClauseError", [
        [Type.atom("__exception__"), Type.boolean(true)],
        [Type.atom("args"), Type.nil()],
        [Type.atom("arity"), Type.integer(2)],
        [Type.atom("clauses"), Type.nil()],
        [Type.atom("function"), Type.atom("my fun")],
        [Type.atom("kind"), Type.nil()],
        [Type.atom("module"), Type.alias("MyModule")],
      ]);

      assert.equal(
        message(struct),
        'no function clause matching in MyModule."my fun"/2',
      );
    });

    it("lists the arguments given to the failed call", () => {
      const struct = structFixture({
        args: Type.list([Type.atom("abc"), Type.integer(123)]),
      });

      assert.equal(
        message(struct),
        "no function clause matching in MyModule.my_fun/2\n\nThe following arguments were given to MyModule.my_fun/2:\n\n    # 1\n    :abc\n\n    # 2\n    123\n",
      );
    });

    it("keeps an argument holding a newline on one line", () => {
      const struct = structFixture({
        args: Type.list([Type.bitstring("a\nb"), Type.integer(123)]),
      });

      assert.equal(
        message(struct),
        'no function clause matching in MyModule.my_fun/2\n\nThe following arguments were given to MyModule.my_fun/2:\n\n    # 1\n    "a\\nb"\n\n    # 2\n    123\n',
      );
    });

    it("renders the attempted clauses, marking what didn't match", () => {
      const struct = structFixture({
        args: Type.list([Type.atom("abc"), Type.integer(123)]),
        kind: Type.atom("def"),
        clauses: Type.list([
          Type.tuple([
            Type.list([blamedNode(false, ":ok"), blamedNode(true, "y")]),
            Type.list([]),
          ]),
          Type.tuple([
            Type.list([blamedNode(true, "x"), blamedNode(true, "y")]),
            Type.list([blamedNode(false, "is_integer(x)")]),
          ]),
        ]),
      });

      assert.equal(
        message(struct),
        "no function clause matching in MyModule.my_fun/2\n\nThe following arguments were given to MyModule.my_fun/2:\n\n    # 1\n    :abc\n\n    # 2\n    123\n\nAttempted function clauses (showing 2 out of 2):\n\n    def my_fun(-:ok-, y)\n    def my_fun(x, y) when -is_integer(x)-\n",
      );
    });

    it("renders a private function's clauses as defp", () => {
      const struct = structFixture({
        args: Type.list([Type.atom("abc"), Type.integer(123)]),
        kind: Type.atom("defp"),
        clauses: Type.list([
          Type.tuple([
            Type.list([blamedNode(true, "x"), blamedNode(true, "y")]),
            Type.list([]),
          ]),
        ]),
      });

      assert.isTrue(message(struct).endsWith("    defp my_fun(x, y)\n"));
    });

    it("renders each guard of a multi-guard clause", () => {
      const struct = structFixture({
        args: Type.list([Type.atom("abc"), Type.integer(123)]),
        kind: Type.atom("def"),
        clauses: Type.list([
          Type.tuple([
            Type.list([blamedNode(true, "x"), blamedNode(true, "y")]),
            Type.list([
              blamedNode(false, "is_integer(x)"),
              blamedNode(true, "is_atom(x)"),
            ]),
          ]),
        ]),
      });

      assert.isTrue(
        message(struct).endsWith(
          "    def my_fun(x, y) when -is_integer(x)- when is_atom(x)\n",
        ),
      );
    });

    it("keeps an and nested in an or unparenthesized", () => {
      const struct = structFixture({
        args: Type.list([Type.atom("abc"), Type.integer(123)]),
        kind: Type.atom("def"),
        clauses: Type.list([
          Type.tuple([
            Type.list([blamedNode(true, "x"), blamedNode(true, "y")]),
            Type.list([
              Type.tuple([
                Type.atom("or"),
                blamedNode(false, "x == :infinity"),
                Type.tuple([
                  Type.atom("and"),
                  blamedNode(true, "is_integer(x)"),
                  blamedNode(false, "x >= 0"),
                ]),
              ]),
            ]),
          ]),
        ]),
      });

      assert.isTrue(
        message(struct).endsWith(
          "    def my_fun(x, y) when -x == :infinity- or is_integer(x) and -x >= 0-\n",
        ),
      );
    });

    it("parenthesizes an or nested in an and", () => {
      const struct = structFixture({
        args: Type.list([Type.atom("abc"), Type.integer(123)]),
        kind: Type.atom("def"),
        clauses: Type.list([
          Type.tuple([
            Type.list([blamedNode(true, "x"), blamedNode(true, "y")]),
            Type.list([
              Type.tuple([
                Type.atom("and"),
                Type.tuple([
                  Type.atom("or"),
                  blamedNode(true, "is_integer(x)"),
                  blamedNode(false, "is_atom(x)"),
                ]),
                blamedNode(false, "x >= 0"),
              ]),
            ]),
          ]),
        ]),
      });

      assert.isTrue(
        message(struct).endsWith(
          "    def my_fun(x, y) when (is_integer(x) or -is_atom(x)-) and -x >= 0-\n",
        ),
      );
    });

    it("counts out a single clause beyond the limit", () => {
      const clause = Type.tuple([
        Type.list([blamedNode(true, "x"), blamedNode(true, "y")]),
        Type.list([]),
      ]);

      const struct = structFixture({
        args: Type.list([Type.atom("abc"), Type.integer(123)]),
        kind: Type.atom("def"),
        clauses: Type.list(Array(11).fill(clause)),
      });

      const text = message(struct);

      assert.isTrue(
        text.includes("Attempted function clauses (showing 10 out of 11):"),
      );

      assert.isTrue(text.endsWith("    ...\n    (1 clause not shown)\n"));
    });

    it("counts out multiple clauses beyond the limit", () => {
      const clause = Type.tuple([
        Type.list([blamedNode(true, "x"), blamedNode(true, "y")]),
        Type.list([]),
      ]);

      const struct = structFixture({
        args: Type.list([Type.atom("abc"), Type.integer(123)]),
        kind: Type.atom("def"),
        clauses: Type.list(Array(12).fill(clause)),
      });

      const text = message(struct);

      assert.isTrue(
        text.includes("Attempted function clauses (showing 10 out of 12):"),
      );

      assert.isTrue(text.endsWith("    ...\n    (2 clauses not shown)\n"));
    });
  });
});
