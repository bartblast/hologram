"use strict";

import {
  assert,
  assertBoxedError,
  defineRuntimeGlobals,
} from "../support/helpers.mjs";

import Erlang_Erl_Kernel_Errors from "../../../assets/js/erlang/erl_kernel_errors.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

const errorInfo = Type.keywordList([
  [
    Type.atom("error_info"),
    Type.map([[Type.atom("module"), Type.atom("erl_kernel_errors")]]),
  ],
]);

function osStacktrace(functionName, argsOrArity) {
  return Type.list([
    Type.tuple([
      Type.atom("os"),
      Type.atom(functionName),
      argsOrArity,
      errorInfo,
    ]),
  ]);
}

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/erl_kernel_errors_test.exs
// Always update both together.

describe("Erlang_Erl_Kernel_Errors", () => {
  describe("format_error/2", () => {
    const format_error = Erlang_Erl_Kernel_Errors["format_error/2"];

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

    it("returns an empty map for a function without a formatter clause", () => {
      const stacktrace = osStacktrace("type", Type.list());

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("returns an empty map when the frame carries an arity", () => {
      const stacktrace = osStacktrace("system_time", Type.integer(1));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("os system_time: invalid time unit", () => {
      const stacktrace = osStacktrace(
        "system_time",
        Type.list([Type.atom("bad")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("invalid time unit")]]),
      );
    });

    it("raises FunctionClauseError when the stacktrace is empty", () => {
      const stacktrace = Type.list();

      assertBoxedError(
        () => format_error(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(
          ":erl_kernel_errors.format_error/2",
          [Type.atom("badarg"), stacktrace],
        ),
      );
    });

    it("raises FunctionClauseError when the top frame is not a 4-tuple", () => {
      const stacktrace = Type.list([Type.tuple([Type.atom("os")])]);

      assertBoxedError(
        () => format_error(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(
          ":erl_kernel_errors.format_error/2",
          [Type.atom("badarg"), stacktrace],
        ),
      );
    });
  });
});
