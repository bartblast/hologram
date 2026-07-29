"use strict";

import {
  assert,
  assertBoxedError,
  defineRuntimeGlobals,
} from "../support/helpers.mjs";

import Erlang_Erl_Erts_Errors from "../../../assets/js/erlang/erl_erts_errors.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

const errorInfo = Type.keywordList([
  [
    Type.atom("error_info"),
    Type.map([[Type.atom("module"), Type.atom("erl_erts_errors")]]),
  ],
]);

function erlangStacktrace(functionName, argsOrArity) {
  return Type.list([
    Type.tuple([
      Type.atom("erlang"),
      Type.atom(functionName),
      argsOrArity,
      errorInfo,
    ]),
  ]);
}

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/erl_erts_errors_test.exs
// Always update both together.

describe("Erlang_Erl_Erts_Errors", () => {
  describe("format_error/2", () => {
    const format_error = Erlang_Erl_Erts_Errors["format_error/2"];

    it("returns an empty map when the module has no formatter", () => {
      const stacktrace = Type.list([
        Type.tuple([
          Type.atom("some_module"),
          Type.atom("f"),
          Type.list([Type.integer(1)]),
          errorInfo,
        ]),
      ]);

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("returns an empty map for a system_limit reason", () => {
      const stacktrace = erlangStacktrace(
        "length",
        Type.list([Type.atom("x")]),
      );

      const result = format_error(Type.atom("system_limit"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("returns an empty map for a function without a formatter clause", () => {
      const stacktrace = erlangStacktrace(
        "++",
        Type.list([Type.atom("x"), Type.list()]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("erlang element: bad index", () => {
      const stacktrace = erlangStacktrace(
        "element",
        Type.list([Type.atom("x"), Type.tuple([Type.atom("a")])]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not an integer")]]),
      );
    });

    it("erlang element: index out of range", () => {
      const stacktrace = erlangStacktrace(
        "element",
        Type.list([Type.integer(0), Type.tuple([Type.atom("a")])]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("out of range")]]),
      );
    });

    it("erlang element: index beyond the tuple size", () => {
      const stacktrace = erlangStacktrace(
        "element",
        Type.list([Type.integer(5), Type.tuple([Type.atom("a")])]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("out of range")]]),
      );
    });

    it("erlang element: not a tuple", () => {
      const stacktrace = erlangStacktrace(
        "element",
        Type.list([Type.integer(1), Type.atom("x")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a tuple")]]),
      );
    });

    it("erlang element: bad index and not a tuple", () => {
      const stacktrace = erlangStacktrace(
        "element",
        Type.list([Type.atom("x"), Type.atom("y")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not an integer")],
          [Type.integer(2), Type.bitstring("not a tuple")],
        ]),
      );
    });

    it("erlang is_map_key: not a map", () => {
      const stacktrace = erlangStacktrace(
        "is_map_key",
        Type.list([Type.atom("k"), Type.atom("x")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a map")]]),
      );
    });

    it("erlang length: not a list", () => {
      const stacktrace = erlangStacktrace(
        "length",
        Type.list([Type.atom("x")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a list")]]),
      );
    });

    it("erlang map_get: key not present in map", () => {
      const stacktrace = erlangStacktrace(
        "map_get",
        Type.list([Type.atom("k"), Type.map()]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not present in map")]]),
      );
    });

    it("erlang map_get: not a map", () => {
      const stacktrace = erlangStacktrace(
        "map_get",
        Type.list([Type.atom("k"), Type.atom("x")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a map")]]),
      );
    });

    it("raises FunctionClauseError when the stacktrace is empty", () => {
      const stacktrace = Type.list();

      assertBoxedError(
        () => format_error(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(
          ":erl_erts_errors.format_error/2",
          [Type.atom("badarg"), stacktrace],
        ),
      );
    });

    it("raises FunctionClauseError when the top frame is not a 4-tuple", () => {
      const stacktrace = Type.list([Type.tuple([Type.atom("erlang")])]);

      assertBoxedError(
        () => format_error(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(
          ":erl_erts_errors.format_error/2",
          [Type.atom("badarg"), stacktrace],
        ),
      );
    });
  });
});
