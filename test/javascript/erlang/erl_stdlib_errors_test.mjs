"use strict";

import {
  assert,
  assertBoxedError,
  contextFixture,
  defineRuntimeGlobals,
} from "../support/helpers.mjs";

import Erlang_Erl_Stdlib_Errors from "../../../assets/js/erlang/erl_stdlib_errors.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

const errorInfo = Type.keywordList([
  [
    Type.atom("error_info"),
    Type.map([[Type.atom("module"), Type.atom("erl_stdlib_errors")]]),
  ],
]);

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/erl_stdlib_errors_test.exs
// Always update both together.

describe("Erlang_Erl_Stdlib_Errors", () => {
  describe("format_error/2", () => {
    const format_error = Erlang_Erl_Stdlib_Errors["format_error/2"];

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

    it("returns an empty map when the frame carries no error_info", () => {
      const stacktrace = Type.list([
        Type.tuple([
          Type.atom("some_module"),
          Type.atom("f"),
          Type.list([Type.integer(1)]),
          Type.list(),
        ]),
      ]);

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("consults only the first stacktrace frame", () => {
      const stacktrace = Type.list([
        Type.tuple([
          Type.atom("some_module"),
          Type.atom("f"),
          Type.list([Type.integer(1)]),
          errorInfo,
        ]),
        Type.tuple([
          Type.atom("maps"),
          Type.atom("get"),
          Type.list([Type.atom("a"), Type.atom("b")]),
          errorInfo,
        ]),
      ]);

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("raises FunctionClauseError when the stacktrace is empty", () => {
      const stacktrace = Type.list();

      assertBoxedError(
        () => format_error(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(
          ":erl_stdlib_errors.format_error/2",
          [Type.atom("badarg"), stacktrace],
        ),
      );
    });

    it("raises FunctionClauseError when the top frame is not a 4-tuple", () => {
      const fun = Type.anonymousFunction(0, [], contextFixture());

      const stacktrace = Type.list([
        Type.tuple([fun, Type.list([Type.integer(1)]), errorInfo]),
      ]);

      assertBoxedError(
        () => format_error(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(
          ":erl_stdlib_errors.format_error/2",
          [Type.atom("badarg"), stacktrace],
        ),
      );
    });
  });
});
