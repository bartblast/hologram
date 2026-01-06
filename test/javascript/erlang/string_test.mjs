"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_String from "../../../assets/js/erlang/string.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/string_test.exs

describe("Erlang_String", () => {
  describe("join/2", () => {
    describe("valid inputs", () => {
      it("single element", () => {
        const stringList = Type.list([Type.charlist("hello")]);
        const separator = Type.charlist(", ");
        const result = Erlang_String["join/2"](stringList, separator);

        assert.deepStrictEqual(result, Type.charlist("hello"));
      });

      it("multiple elements", () => {
        const stringList = Type.list([
          Type.charlist("one"),
          Type.charlist("two"),
          Type.charlist("three"),
        ]);
        const separator = Type.charlist(", ");
        const result = Erlang_String["join/2"](stringList, separator);

        assert.deepStrictEqual(result, Type.charlist("one, two, three"));
      });

      it("empty separator", () => {
        const stringList = Type.list([
          Type.charlist("hello"),
          Type.charlist("world"),
        ]);
        const separator = Type.charlist("");
        const result = Erlang_String["join/2"](stringList, separator);

        assert.deepStrictEqual(result, Type.charlist("helloworld"));
      });

      it("empty strings (charlists) in list", () => {
        const stringList = Type.list([
          Type.charlist(""),
          Type.charlist("hello"),
          Type.charlist(""),
          Type.charlist("world"),
          Type.charlist(""),
        ]);
        const separator = Type.charlist("-");
        const result = Erlang_String["join/2"](stringList, separator);

        assert.deepStrictEqual(result, Type.charlist("-hello--world-"));
      });

      it("multi-character separator", () => {
        const stringList = Type.list([
          Type.charlist("apple"),
          Type.charlist("banana"),
          Type.charlist("cherry"),
        ]);
        const separator = Type.charlist(" and ");
        const result = Erlang_String["join/2"](stringList, separator);

        assert.deepStrictEqual(
          result,
          Type.charlist("apple and banana and cherry"),
        );
      });

      it("empty list", () => {
        const stringList = Type.list([]);
        const separator = Type.charlist(", ");
        const result = Erlang_String["join/2"](stringList, separator);

        assert.deepStrictEqual(result, Type.list([]));
      });
    });

    describe("error conditions", () => {
      it("first argument is not a list", () => {
        const stringList = Type.atom("not_a_list");
        const separator = Type.charlist(", ");

        assertBoxedError(
          () => Erlang_String["join/2"](stringList, separator),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":string.join/2", [
            stringList,
            separator,
          ]),
        );
      });

      it("first argument is an improper list", () => {
        const stringList = Type.improperList([
          Type.charlist("hello"),
          Type.atom("tail"),
        ]);
        const separator = Type.charlist(", ");

        assertBoxedError(
          () => Erlang_String["join/2"](stringList, separator),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":string.join/2", [
            stringList,
            separator,
          ]),
        );
      });

      it("second argument is not a proper list", () => {
        const stringList = Type.list([Type.charlist("hello")]);
        const separator = Type.atom("not_a_list");

        assertBoxedError(
          () => Erlang_String["join/2"](stringList, separator),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":string.join/2", [
            stringList,
            separator,
          ]),
        );
      });

      it("separator is not a charlist (list of atoms)", () => {
        const stringList = Type.list([Type.charlist("hello")]);
        const separator = Type.list([Type.atom("a"), Type.atom("b")]);

        assertBoxedError(
          () => Erlang_String["join/2"](stringList, separator),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":string.join/2", [
            stringList,
            separator,
          ]),
        );
      });

      it("list contains non-charlist element", () => {
        const stringList = Type.list([
          Type.charlist("hello"),
          Type.atom("not_a_charlist"),
        ]);
        const separator = Type.charlist(", ");

        assertBoxedError(
          () => Erlang_String["join/2"](stringList, separator),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":string.join/2", [
            stringList,
            separator,
          ]),
        );
      });
    });
  });
});
