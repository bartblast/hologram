"use strict";

import {
  assert,
  assertBoxedError,
  charlistFixture,
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
        const stringList = Type.list([charlistFixture("hello")]);
        const separator = charlistFixture(", ");
        const result = Erlang_String["join/2"](stringList, separator);

        assert.deepStrictEqual(result, charlistFixture("hello"));
      });

      it("multiple elements", () => {
        const stringList = Type.list([
          charlistFixture("one"),
          charlistFixture("two"),
          charlistFixture("three"),
        ]);
        const separator = charlistFixture(", ");
        const result = Erlang_String["join/2"](stringList, separator);

        assert.deepStrictEqual(result, charlistFixture("one, two, three"));
      });

      it("empty separator", () => {
        const stringList = Type.list([
          charlistFixture("hello"),
          charlistFixture("world"),
        ]);
        const separator = charlistFixture("");
        const result = Erlang_String["join/2"](stringList, separator);

        assert.deepStrictEqual(result, charlistFixture("helloworld"));
      });

      it("empty strings (charlists) in list", () => {
        const stringList = Type.list([
          charlistFixture(""),
          charlistFixture("hello"),
          charlistFixture(""),
          charlistFixture("world"),
          charlistFixture(""),
        ]);
        const separator = charlistFixture("-");
        const result = Erlang_String["join/2"](stringList, separator);

        assert.deepStrictEqual(result, charlistFixture("-hello--world-"));
      });

      it("multi-character separator", () => {
        const stringList = Type.list([
          charlistFixture("apple"),
          charlistFixture("banana"),
          charlistFixture("cherry"),
        ]);
        const separator = charlistFixture(" and ");
        const result = Erlang_String["join/2"](stringList, separator);

        assert.deepStrictEqual(
          result,
          charlistFixture("apple and banana and cherry"),
        );
      });
    });

    describe("error conditions", () => {
      it("empty list", () => {
        const stringList = Type.list([]);
        const separator = charlistFixture(", ");

        assertBoxedError(
          () => Erlang_String["join/2"](stringList, separator),
          "FunctionClauseError",
          Interpreter.buildFunctionClauseErrorMsg(":string.join/2", [
            stringList,
            separator,
          ]),
        );
      });

      it("first argument is not a list", () => {
        const stringList = Type.atom("not_a_list");
        const separator = charlistFixture(", ");

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
