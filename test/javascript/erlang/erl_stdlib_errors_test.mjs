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

function mapsStacktrace(functionName, argsOrArity) {
  return Type.list([
    Type.tuple([
      Type.atom("maps"),
      Type.atom(functionName),
      argsOrArity,
      errorInfo,
    ]),
  ]);
}

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

    it("maps find: not a map", () => {
      const stacktrace = mapsStacktrace(
        "find",
        Type.list([Type.atom("a"), Type.atom("b")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a map")]]),
      );
    });

    it("maps fold: bad fun and bad collection", () => {
      const stacktrace = mapsStacktrace(
        "fold",
        Type.list([Type.atom("a"), Type.atom("b"), Type.atom("c")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not a fun that takes three arguments"),
          ],
          [Type.integer(3), Type.bitstring("not a map or an iterator")],
        ]),
      );
    });

    it("maps fold: valid fun and iterator skip their fragments", () => {
      const fun = Type.anonymousFunction(3, [], contextFixture());

      const iterator = Type.improperList([
        Type.integer(0),
        Type.map([[Type.atom("a"), Type.integer(1)]]),
      ]);

      const stacktrace = mapsStacktrace(
        "fold",
        Type.list([fun, Type.atom("b"), iterator]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("maps fold: iterator validity is checked recursively", () => {
      const fun = Type.anonymousFunction(3, [], contextFixture());

      const invalidIterator = Type.tuple([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const stacktrace = mapsStacktrace(
        "fold",
        Type.list([fun, Type.atom("b"), invalidIterator]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(3), Type.bitstring("not a map or an iterator")],
        ]),
      );
    });

    it("maps from_keys: improper list", () => {
      const stacktrace = mapsStacktrace(
        "from_keys",
        Type.list([
          Type.improperList([Type.integer(1), Type.integer(2)]),
          Type.atom("a"),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a proper list")]]),
      );
    });

    it("maps from_list: not a list", () => {
      const stacktrace = mapsStacktrace(
        "from_list",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a list")]]),
      );
    });

    it("maps get/2: key not present in map", () => {
      const stacktrace = mapsStacktrace(
        "get",
        Type.list([
          Type.atom("a"),
          Type.map([[Type.atom("b"), Type.integer(2)]]),
        ]),
      );

      const result = format_error(Type.atom("badkey"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not present in map")]]),
      );
    });

    it("maps get/2: not a map", () => {
      const stacktrace = mapsStacktrace(
        "get",
        Type.list([Type.atom("a"), Type.atom("b")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a map")]]),
      );
    });

    it("maps get/3: not a map", () => {
      const stacktrace = mapsStacktrace(
        "get",
        Type.list([Type.atom("a"), Type.atom("b"), Type.atom("c")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a map")]]),
      );
    });

    it("maps intersect: both arguments not maps", () => {
      const stacktrace = mapsStacktrace(
        "intersect",
        Type.list([Type.atom("a"), Type.atom("b")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not a map")],
          [Type.integer(2), Type.bitstring("not a map")],
        ]),
      );
    });

    it("maps intersect_with: bad fun and bad maps", () => {
      const stacktrace = mapsStacktrace(
        "intersect_with",
        Type.list([Type.atom("a"), Type.atom("b"), Type.atom("c")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not a fun that takes three arguments"),
          ],
          [Type.integer(2), Type.bitstring("not a map")],
          [Type.integer(3), Type.bitstring("not a map")],
        ]),
      );
    });

    it("maps is_key: not a map", () => {
      const stacktrace = mapsStacktrace(
        "is_key",
        Type.list([Type.atom("a"), Type.atom("b")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a map")]]),
      );
    });

    it("maps iterator: not a map", () => {
      const stacktrace = mapsStacktrace(
        "iterator",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a map")]]),
      );
    });

    it("maps keys: not a map", () => {
      const stacktrace = mapsStacktrace("keys", Type.list([Type.atom("a")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a map")]]),
      );
    });

    it("maps map: bad fun and bad collection", () => {
      const stacktrace = mapsStacktrace(
        "map",
        Type.list([Type.atom("a"), Type.atom("b")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not a fun that takes two arguments"),
          ],
          [Type.integer(2), Type.bitstring("not a map or an iterator")],
        ]),
      );
    });

    it("maps merge: both arguments not maps", () => {
      const stacktrace = mapsStacktrace(
        "merge",
        Type.list([Type.atom("a"), Type.atom("b")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not a map")],
          [Type.integer(2), Type.bitstring("not a map")],
        ]),
      );
    });

    it("maps merge_with: bad fun and bad maps", () => {
      const stacktrace = mapsStacktrace(
        "merge_with",
        Type.list([Type.atom("a"), Type.atom("b"), Type.atom("c")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not a fun that takes three arguments"),
          ],
          [Type.integer(2), Type.bitstring("not a map")],
          [Type.integer(3), Type.bitstring("not a map")],
        ]),
      );
    });

    it("maps next: bad iterator", () => {
      const stacktrace = mapsStacktrace("next", Type.list([Type.atom("a")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a valid iterator")]]),
      );
    });

    it("maps put: not a map", () => {
      const stacktrace = mapsStacktrace(
        "put",
        Type.list([Type.atom("a"), Type.atom("b"), Type.atom("c")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(3), Type.bitstring("not a map")]]),
      );
    });

    it("maps remove: not a map", () => {
      const stacktrace = mapsStacktrace(
        "remove",
        Type.list([Type.atom("a"), Type.atom("b")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a map")]]),
      );
    });

    it("maps take: not a map", () => {
      const stacktrace = mapsStacktrace(
        "take",
        Type.list([Type.atom("a"), Type.atom("b")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a map")]]),
      );
    });

    it("maps to_list: not a map or iterator", () => {
      const stacktrace = mapsStacktrace("to_list", Type.list([Type.atom("a")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not a map or an iterator")],
        ]),
      );
    });

    it("maps update: key not present in map", () => {
      const stacktrace = mapsStacktrace(
        "update",
        Type.list([
          Type.atom("a"),
          Type.integer(1),
          Type.map([[Type.atom("b"), Type.integer(2)]]),
        ]),
      );

      const result = format_error(Type.atom("badkey"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not present in map")]]),
      );
    });

    it("maps update: not a map", () => {
      const stacktrace = mapsStacktrace(
        "update",
        Type.list([Type.atom("a"), Type.integer(1), Type.atom("b")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(3), Type.bitstring("not a map")]]),
      );
    });

    it("maps values: not a map", () => {
      const stacktrace = mapsStacktrace("values", Type.list([Type.atom("a")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a map")]]),
      );
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

    it("raises FunctionClauseError when a maps clause needs args but the frame carries an arity", () => {
      const stacktrace = mapsStacktrace("get", Type.integer(2));

      assertBoxedError(
        () => format_error(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(
          ":erl_stdlib_errors.format_maps_error/2",
          [Type.atom("get"), Type.integer(2)],
        ),
      );
    });
  });
});
