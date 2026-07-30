"use strict";

import {
  assert,
  assertBoxedError,
  contextFixture,
  defineRuntimeGlobals,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
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
  describe("format_bs_fail/2", () => {
    const format_bs_fail = Erlang_Erl_Erts_Errors["format_bs_fail/2"];

    const bsStacktrace = (errorInfoMap) =>
      Type.list([
        Type.tuple([
          Type.atom("m"),
          Type.atom("f"),
          Type.integer(1),
          Type.keywordList([[Type.atom("error_info"), errorInfoMap]]),
        ]),
      ]);

    const causeErrorInfo = (cause) => Type.map([[Type.atom("cause"), cause]]);

    const expectedResult = (general) =>
      Type.map([
        [Type.atom("general"), Type.bitstring(general)],
        [Type.atom("reason"), Type.bitstring("construction of binary failed")],
      ]);

    const inspectPrettyPrinter = () =>
      Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("value")],
            guards: [],
            body: (context) =>
              Type.bitstring(Interpreter.inspect(context.vars.value)),
          },
        ],
        contextFixture(),
      );

    it("returns an empty map when the error_info carries no cause", () => {
      const stacktrace = bsStacktrace(
        Type.map([[Type.atom("module"), Type.atom("erl_erts_errors")]]),
      );

      const result = format_bs_fail(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("returns an empty map when the frame carries no error_info", () => {
      const stacktrace = Type.list([
        Type.tuple([
          Type.atom("m"),
          Type.atom("f"),
          Type.integer(1),
          Type.list(),
        ]),
      ]);

      const result = format_bs_fail(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("formats an integer type mismatch", () => {
      const cause = Type.tuple([
        Type.integer(1),
        Type.atom("integer"),
        Type.atom("type"),
        Type.float(1.5),
      ]);

      const result = format_bs_fail(
        Type.atom("badarg"),
        bsStacktrace(causeErrorInfo(cause)),
      );

      assert.deepStrictEqual(
        result,
        expectedResult(
          "segment 1 of type 'integer': expected an integer but got: 1.5",
        ),
      );
    });

    it("formats a binary type mismatch", () => {
      const cause = Type.tuple([
        Type.integer(1),
        Type.atom("binary"),
        Type.atom("type"),
        Type.integer(5),
      ]);

      const result = format_bs_fail(
        Type.atom("badarg"),
        bsStacktrace(causeErrorInfo(cause)),
      );

      assert.deepStrictEqual(
        result,
        expectedResult(
          "segment 1 of type 'binary': expected a binary but got: 5",
        ),
      );
    });

    it("formats a utf type mismatch", () => {
      const cause = Type.tuple([
        Type.integer(2),
        Type.atom("utf8"),
        Type.atom("type"),
        Type.integer(5),
      ]);

      const result = format_bs_fail(
        Type.atom("badarg"),
        bsStacktrace(causeErrorInfo(cause)),
      );

      assert.deepStrictEqual(
        result,
        expectedResult(
          "segment 2 of type 'utf8': expected a non-negative integer encodable as utf8 but got: 5",
        ),
      );
    });

    it("formats an invalid float size", () => {
      const cause = Type.tuple([
        Type.integer(1),
        Type.atom("float"),
        Type.atom("invalid"),
        Type.integer(8),
      ]);

      const result = format_bs_fail(
        Type.atom("badarg"),
        bsStacktrace(causeErrorInfo(cause)),
      );

      assert.deepStrictEqual(
        result,
        expectedResult(
          "segment 1 of type 'float': expected one of the supported sizes 16, 32, or 64 but got: 8",
        ),
      );
    });

    it("formats a short value", () => {
      const cause = Type.tuple([
        Type.integer(1),
        Type.atom("integer"),
        Type.atom("short"),
        Type.integer(5),
      ]);

      const result = format_bs_fail(
        Type.atom("badarg"),
        bsStacktrace(causeErrorInfo(cause)),
      );

      assert.deepStrictEqual(
        result,
        expectedResult(
          "segment 1 of type 'integer': the value 5 is shorter than the size of the segment",
        ),
      );
    });

    it("formats an invalid size", () => {
      const cause = Type.tuple([
        Type.integer(1),
        Type.atom("integer"),
        Type.atom("size"),
        Type.integer(-1),
      ]);

      const result = format_bs_fail(
        Type.atom("badarg"),
        bsStacktrace(causeErrorInfo(cause)),
      );

      assert.deepStrictEqual(
        result,
        expectedResult(
          "segment 1 of type 'integer': expected a non-negative integer as size but got: -1",
        ),
      );
    });

    it("honors the override_segment_position", () => {
      const cause = Type.tuple([
        Type.integer(1),
        Type.atom("integer"),
        Type.atom("type"),
        Type.integer(5),
      ]);

      const errorInfoMap = Type.map([
        [Type.atom("cause"), cause],
        [Type.atom("override_segment_position"), Type.integer(3)],
      ]);

      const result = format_bs_fail(
        Type.atom("badarg"),
        bsStacktrace(errorInfoMap),
      );

      assert.deepStrictEqual(
        result,
        expectedResult(
          "segment 3 of type 'integer': expected an integer but got: 5",
        ),
      );
    });

    it("applies the error_info pretty printer", () => {
      const cause = Type.tuple([
        Type.integer(1),
        Type.atom("binary"),
        Type.atom("unit"),
        Type.bitstring([0, 0, 1]),
      ]);

      const errorInfoMap = Type.map([
        [Type.atom("cause"), cause],
        [Type.atom("pretty_printer"), inspectPrettyPrinter()],
      ]);

      const result = format_bs_fail(
        Type.atom("badarg"),
        bsStacktrace(errorInfoMap),
      );

      assert.deepStrictEqual(
        result,
        expectedResult(
          "segment 1 of type 'binary': the size of the value <<1::size(3)>> is not a multiple of the unit for the segment",
        ),
      );
    });

    it("formats a float outside the expressible range with the pretty printer", () => {
      const cause = Type.tuple([
        Type.integer(1),
        Type.atom("float"),
        Type.atom("no_float"),
        Type.atom("abc"),
      ]);

      const errorInfoMap = Type.map([
        [Type.atom("cause"), cause],
        [Type.atom("pretty_printer"), inspectPrettyPrinter()],
      ]);

      const result = format_bs_fail(
        Type.atom("badarg"),
        bsStacktrace(errorInfoMap),
      );

      assert.deepStrictEqual(
        result,
        expectedResult(
          "segment 1 of type 'float': the value :abc is outside the range expressible as a float",
        ),
      );
    });

    it("formats a too large size for a system_limit reason", () => {
      const cause = Type.tuple([
        Type.integer(1),
        Type.atom("integer"),
        Type.atom("size"),
        Type.integer(99),
      ]);

      const result = format_bs_fail(
        Type.atom("system_limit"),
        bsStacktrace(causeErrorInfo(cause)),
      );

      assert.deepStrictEqual(
        result,
        expectedResult("segment 1 of type 'integer': the size 99 is too large"),
      );
    });

    it("formats a too large binary for a system_limit reason", () => {
      const cause = Type.tuple([
        Type.integer(1),
        Type.atom("binary"),
        Type.atom("binary"),
        Type.atom("size"),
      ]);

      const result = format_bs_fail(
        Type.atom("system_limit"),
        bsStacktrace(causeErrorInfo(cause)),
      );

      assert.deepStrictEqual(
        result,
        expectedResult(
          "segment 1 of type 'binary': the size of the binary/bitstring is too large (exceeding 2147483647 bits)",
        ),
      );
    });

    it("raises FunctionClauseError when the stacktrace is empty", () => {
      const stacktrace = Type.list();

      assertBoxedError(
        () => format_bs_fail(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg(
          ":erl_erts_errors.format_bs_fail/2",
          [Type.atom("badarg"), stacktrace],
        ),
      );
    });
  });

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

    it("erlang atom_to_binary/1: not an atom", () => {
      const stacktrace = erlangStacktrace(
        "atom_to_binary",
        Type.list([Type.integer(1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not an atom")]]),
      );
    });

    it("erlang atom_to_binary/2: not an atom", () => {
      const stacktrace = erlangStacktrace(
        "atom_to_binary",
        Type.list([Type.integer(1), Type.atom("utf8")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not an atom")]]),
      );
    });

    it("erlang atom_to_binary/2: latin1-inexpressible atom", () => {
      const stacktrace = erlangStacktrace(
        "atom_to_binary",
        Type.list([Type.atom("hologram"), Type.atom("latin1")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("contains a character not expressible in latin1"),
          ],
        ]),
      );
    });

    it("erlang atom_to_binary/2: invalid encoding", () => {
      const stacktrace = erlangStacktrace(
        "atom_to_binary",
        Type.list([Type.atom("a"), Type.atom("bad")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(2), Type.bitstring("is an invalid encoding option")],
        ]),
      );
    });

    it("erlang atom_to_list: not an atom", () => {
      const stacktrace = erlangStacktrace(
        "atom_to_list",
        Type.list([Type.integer(1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not an atom")]]),
      );
    });

    it("erlang binary_to_atom/1: not a binary", () => {
      const stacktrace = erlangStacktrace(
        "binary_to_atom",
        Type.list([Type.integer(1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a binary")]]),
      );
    });

    it("erlang binary_to_atom/1: invalid UTF-8", () => {
      const stacktrace = erlangStacktrace(
        "binary_to_atom",
        Type.list([Bitstring.fromBytes([255])]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("invalid UTF8 encoding")]]),
      );
    });

    it("erlang binary_to_atom/2: invalid encoding", () => {
      const stacktrace = erlangStacktrace(
        "binary_to_atom",
        Type.list([Type.bitstring("a"), Type.atom("bad")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(2),
            Type.bitstring("not one of the atoms: latin1, utf8, or unicode"),
          ],
        ]),
      );
    });

    it("erlang binary_to_atom/2: latin1 with a non-binary", () => {
      const stacktrace = erlangStacktrace(
        "binary_to_atom",
        Type.list([Type.integer(1), Type.atom("latin1")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a binary")]]),
      );
    });

    it("erlang binary_to_existing_atom/1: valid binary", () => {
      const stacktrace = erlangStacktrace(
        "binary_to_existing_atom",
        Type.list([Type.bitstring("nonexistent")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not an already existing atom")],
        ]),
      );
    });

    it("erlang binary_to_float: not a binary", () => {
      const stacktrace = erlangStacktrace(
        "binary_to_float",
        Type.list([Type.integer(1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a binary")]]),
      );
    });

    it("erlang binary_to_float: bad content", () => {
      const stacktrace = erlangStacktrace(
        "binary_to_float",
        Type.list([Type.bitstring("abc")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.list([
              Type.bitstring("not a textual representation of "),
              Type.bitstring("a float"),
            ]),
          ],
        ]),
      );
    });

    it("erlang binary_to_integer/1: bad content", () => {
      const stacktrace = erlangStacktrace(
        "binary_to_integer",
        Type.list([Type.bitstring("abc")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.list([
              Type.bitstring("not a textual representation of "),
              Type.bitstring("an integer"),
            ]),
          ],
        ]),
      );
    });

    it("erlang binary_to_integer/2: bad base", () => {
      const stacktrace = erlangStacktrace(
        "binary_to_integer",
        Type.list([Type.bitstring("abc"), Type.integer(50)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(2),
            Type.bitstring("not an integer in the range 2 through 36"),
          ],
        ]),
      );
    });

    it("erlang binary_to_integer/2: not a binary and bad base", () => {
      const stacktrace = erlangStacktrace(
        "binary_to_integer",
        Type.list([Type.integer(1), Type.integer(50)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not a binary")],
          [
            Type.integer(2),
            Type.bitstring("not an integer in the range 2 through 36"),
          ],
        ]),
      );
    });

    it("erlang binary_to_list: not a binary", () => {
      const stacktrace = erlangStacktrace(
        "binary_to_list",
        Type.list([Type.integer(1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a binary")]]),
      );
    });

    it("erlang binary_to_term: bad content", () => {
      const stacktrace = erlangStacktrace(
        "binary_to_term",
        Type.list([Type.bitstring("abc")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("invalid external representation of a term"),
          ],
        ]),
      );
    });

    it("erlang binary_to_term: not a binary", () => {
      const stacktrace = erlangStacktrace(
        "binary_to_term",
        Type.list([Type.integer(1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a binary")]]),
      );
    });

    it("erlang bit_size: not a bitstring", () => {
      const stacktrace = erlangStacktrace(
        "bit_size",
        Type.list([Type.integer(1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a bitstring")]]),
      );
    });

    it("erlang byte_size: not a bitstring", () => {
      const stacktrace = erlangStacktrace(
        "byte_size",
        Type.list([Type.integer(1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a bitstring")]]),
      );
    });

    it("erlang ceil: not a number", () => {
      const stacktrace = erlangStacktrace("ceil", Type.list([Type.atom("a")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a number")]]),
      );
    });

    it("erlang floor: not a number", () => {
      const stacktrace = erlangStacktrace("floor", Type.list([Type.atom("a")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a number")]]),
      );
    });

    it("erlang float_to_binary/1: not a float", () => {
      const stacktrace = erlangStacktrace(
        "float_to_binary",
        Type.list([Type.integer(1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a float")]]),
      );
    });

    it("erlang float_to_binary/2: bad option", () => {
      const stacktrace = erlangStacktrace(
        "float_to_binary",
        Type.list([Type.float(1.0), Type.list([Type.atom("bad")])]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("invalid option in list")]]),
      );
    });

    it("erlang float_to_binary/2: not a float", () => {
      const stacktrace = erlangStacktrace(
        "float_to_binary",
        Type.list([Type.integer(1), Type.list([Type.atom("bad")])]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a float")]]),
      );
    });

    it("erlang float_to_binary/2: improper options", () => {
      const stacktrace = erlangStacktrace(
        "float_to_binary",
        Type.list([
          Type.float(1.0),
          Type.improperList([Type.atom("a"), Type.atom("b")]),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a proper list")]]),
      );
    });

    it("erlang float_to_list/1: not a float", () => {
      const stacktrace = erlangStacktrace(
        "float_to_list",
        Type.list([Type.integer(1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a float")]]),
      );
    });

    it("erlang integer_to_binary/1: not an integer", () => {
      const stacktrace = erlangStacktrace(
        "integer_to_binary",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not an integer")]]),
      );
    });

    it("erlang integer_to_binary/2: bad base", () => {
      const stacktrace = erlangStacktrace(
        "integer_to_binary",
        Type.list([Type.integer(1), Type.integer(50)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(2),
            Type.bitstring("not an integer in the range 2 through 36"),
          ],
        ]),
      );
    });

    it("erlang integer_to_list/1: not an integer", () => {
      const stacktrace = erlangStacktrace(
        "integer_to_list",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not an integer")]]),
      );
    });

    it("erlang integer_to_list/2: not an integer and bad base", () => {
      const stacktrace = erlangStacktrace(
        "integer_to_list",
        Type.list([Type.atom("a"), Type.integer(50)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not an integer")],
          [
            Type.integer(2),
            Type.bitstring("not an integer in the range 2 through 36"),
          ],
        ]),
      );
    });

    it("erlang list_to_atom: not a list", () => {
      const stacktrace = erlangStacktrace(
        "list_to_atom",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a list")]]),
      );
    });

    it("erlang list_to_atom: improper list", () => {
      const stacktrace = erlangStacktrace(
        "list_to_atom",
        Type.list([Type.improperList([Type.integer(97), Type.integer(98)])]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a proper list")]]),
      );
    });

    it("erlang list_to_atom: bad content", () => {
      const stacktrace = erlangStacktrace(
        "list_to_atom",
        Type.list([Type.list([Type.atom("a")])]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not a list of characters")],
        ]),
      );
    });

    it("erlang list_to_binary: not an iolist", () => {
      const stacktrace = erlangStacktrace(
        "list_to_binary",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not an iolist term")]]),
      );
    });

    it("erlang list_to_existing_atom: flat char list", () => {
      const stacktrace = erlangStacktrace(
        "list_to_existing_atom",
        Type.list([Type.list([Type.integer(104), Type.integer(105)])]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not an already existing atom")],
        ]),
      );
    });

    it("erlang list_to_existing_atom: bad content", () => {
      const stacktrace = erlangStacktrace(
        "list_to_existing_atom",
        Type.list([Type.list([Type.atom("a")])]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not a list of characters")],
        ]),
      );
    });

    it("erlang list_to_float: bad content", () => {
      const stacktrace = erlangStacktrace(
        "list_to_float",
        Type.list([Type.list([Type.integer(97)])]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.list([
              Type.bitstring("not a textual representation of "),
              Type.bitstring("a float"),
            ]),
          ],
        ]),
      );
    });

    it("erlang list_to_float: not a list", () => {
      const stacktrace = erlangStacktrace(
        "list_to_float",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a list")]]),
      );
    });

    it("erlang list_to_float: improper list", () => {
      const stacktrace = erlangStacktrace(
        "list_to_float",
        Type.list([Type.improperList([Type.integer(97), Type.integer(98)])]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a list")]]),
      );
    });

    it("erlang list_to_integer/1: bad content", () => {
      const stacktrace = erlangStacktrace(
        "list_to_integer",
        Type.list([Type.list([Type.integer(97)])]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.list([
              Type.bitstring("not a textual representation of "),
              Type.bitstring("an integer"),
            ]),
          ],
        ]),
      );
    });

    it("erlang list_to_integer/2: bad base", () => {
      const stacktrace = erlangStacktrace(
        "list_to_integer",
        Type.list([Type.list([Type.integer(97)]), Type.integer(50)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(2),
            Type.bitstring("not an integer in the range 2 through 36"),
          ],
        ]),
      );
    });

    it("erlang list_to_integer/2: not a list and bad base", () => {
      const stacktrace = erlangStacktrace(
        "list_to_integer",
        Type.list([Type.atom("a"), Type.integer(50)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not a list")],
          [
            Type.integer(2),
            Type.bitstring("not an integer in the range 2 through 36"),
          ],
        ]),
      );
    });

    it("erlang list_to_pid: bad content", () => {
      const stacktrace = erlangStacktrace(
        "list_to_pid",
        Type.list([Type.list([Type.integer(97)])]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.list([
              Type.bitstring("not a textual representation of "),
              Type.bitstring("a pid"),
            ]),
          ],
        ]),
      );
    });

    it("erlang list_to_ref: bad content", () => {
      const stacktrace = erlangStacktrace(
        "list_to_ref",
        Type.list([Type.list([Type.integer(97)])]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.list([
              Type.bitstring("not a textual representation of "),
              Type.bitstring("a reference"),
            ]),
          ],
        ]),
      );
    });

    it("erlang list_to_tuple: not a list", () => {
      const stacktrace = erlangStacktrace(
        "list_to_tuple",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a list")]]),
      );
    });

    it("erlang tuple_to_list: not a tuple", () => {
      const stacktrace = erlangStacktrace(
        "tuple_to_list",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a tuple")]]),
      );
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

    it("erlang abs: not a number", () => {
      const stacktrace = erlangStacktrace("abs", Type.list([Type.atom("a")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a number")]]),
      );
    });

    it("erlang append_element: not a tuple", () => {
      const stacktrace = erlangStacktrace(
        "append_element",
        Type.list([Type.atom("a"), Type.atom("b")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a tuple")]]),
      );
    });

    it("erlang apply: bad module and args", () => {
      const stacktrace = erlangStacktrace(
        "apply",
        Type.list([Type.integer(1), Type.atom("f"), Type.atom("bad")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not an atom")],
          [Type.integer(3), Type.bitstring("not a list")],
        ]),
      );
    });

    it("erlang binary_part: bad positions", () => {
      const stacktrace = erlangStacktrace(
        "binary_part",
        Type.list([Type.bitstring("abc"), Type.atom("a"), Type.atom("b")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(2), Type.bitstring("not an integer")],
          [Type.integer(3), Type.bitstring("not an integer")],
        ]),
      );
    });

    it("erlang binary_part: start out of range", () => {
      const stacktrace = erlangStacktrace(
        "binary_part",
        Type.list([Type.bitstring("abc"), Type.integer(5), Type.integer(1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("out of range")]]),
      );
    });

    it("erlang binary_part: length out of range", () => {
      const stacktrace = erlangStacktrace(
        "binary_part",
        Type.list([Type.bitstring("abc"), Type.integer(1), Type.integer(5)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(3), Type.bitstring("out of range")]]),
      );
    });

    it("erlang convert_time_unit: bad time and unit", () => {
      const stacktrace = erlangStacktrace(
        "convert_time_unit",
        Type.list([Type.atom("a"), Type.atom("second"), Type.atom("bad")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not an integer")],
          [Type.integer(3), Type.bitstring("invalid time unit")],
        ]),
      );
    });

    it("erlang delete_element delegates to the element clause", () => {
      const stacktrace = erlangStacktrace(
        "delete_element",
        Type.list([Type.atom("a"), Type.atom("b")]),
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

    it("erlang float: not a number", () => {
      const stacktrace = erlangStacktrace("float", Type.list([Type.atom("a")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a number")]]),
      );
    });

    it("erlang fun_info: not a fun", () => {
      const stacktrace = erlangStacktrace(
        "fun_info",
        Type.list([Type.integer(1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a fun")]]),
      );
    });

    it("erlang function_exported: bad args", () => {
      const stacktrace = erlangStacktrace(
        "function_exported",
        Type.list([Type.integer(1), Type.integer(2), Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not an atom")],
          [Type.integer(2), Type.bitstring("not an atom")],
          [Type.integer(3), Type.bitstring("not an integer")],
        ]),
      );
    });

    it("erlang hd: not a nonempty list", () => {
      const stacktrace = erlangStacktrace("hd", Type.list([Type.atom("a")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a nonempty list")]]),
      );
    });

    it("erlang insert_element delegates to the element clause", () => {
      const stacktrace = erlangStacktrace(
        "insert_element",
        Type.list([Type.atom("a"), Type.atom("b"), Type.atom("c")]),
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

    it("erlang iolist_to_binary: not an iodata term", () => {
      const stacktrace = erlangStacktrace(
        "iolist_to_binary",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not an iodata term")]]),
      );
    });

    it("erlang make_fun: bad args", () => {
      const stacktrace = erlangStacktrace(
        "make_fun",
        Type.list([Type.integer(1), Type.integer(2), Type.integer(-1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not an atom")],
          [Type.integer(2), Type.bitstring("not an atom")],
          [Type.integer(3), Type.bitstring("out of range")],
        ]),
      );
    });

    it("erlang make_tuple/2: bad arity", () => {
      const stacktrace = erlangStacktrace(
        "make_tuple",
        Type.list([Type.atom("a"), Type.atom("b")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("out of range")]]),
      );
    });

    it("erlang monotonic_time: invalid time unit", () => {
      const stacktrace = erlangStacktrace(
        "monotonic_time",
        Type.list([Type.atom("bad")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("invalid time unit")]]),
      );
    });

    it("erlang pid_to_list: not a pid", () => {
      const stacktrace = erlangStacktrace(
        "pid_to_list",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a pid")]]),
      );
    });

    it("erlang ref_to_list: not a reference", () => {
      const stacktrace = erlangStacktrace(
        "ref_to_list",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a reference")]]),
      );
    });

    it("erlang round: not a number", () => {
      const stacktrace = erlangStacktrace("round", Type.list([Type.atom("a")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a number")]]),
      );
    });

    it("erlang setelement delegates to the element clause", () => {
      const stacktrace = erlangStacktrace(
        "setelement",
        Type.list([
          Type.integer(0),
          Type.tuple([Type.atom("a")]),
          Type.atom("x"),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("out of range")]]),
      );
    });

    it("erlang split_binary: bad args", () => {
      const stacktrace = erlangStacktrace(
        "split_binary",
        Type.list([Type.atom("a"), Type.integer(-1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not a binary")],
          [Type.integer(2), Type.bitstring("out of range")],
        ]),
      );
    });

    it("erlang split_binary: position out of range", () => {
      const stacktrace = erlangStacktrace(
        "split_binary",
        Type.list([Type.bitstring("abc"), Type.integer(5)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("out of range")]]),
      );
    });

    it("erlang system_info: invalid item", () => {
      const stacktrace = erlangStacktrace(
        "system_info",
        Type.list([Type.atom("bad")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("invalid system info item")],
        ]),
      );
    });

    it("erlang system_time: invalid time unit", () => {
      const stacktrace = erlangStacktrace(
        "system_time",
        Type.list([Type.atom("bad")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("invalid time unit")]]),
      );
    });

    it("erlang time_offset: invalid time unit", () => {
      const stacktrace = erlangStacktrace(
        "time_offset",
        Type.list([Type.atom("bad")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("invalid time unit")]]),
      );
    });

    it("erlang tl: not a nonempty list", () => {
      const stacktrace = erlangStacktrace("tl", Type.list([Type.list()]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a nonempty list")]]),
      );
    });

    it("erlang trunc: not a number", () => {
      const stacktrace = erlangStacktrace("trunc", Type.list([Type.atom("a")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a number")]]),
      );
    });

    it("erlang tuple_size: not a tuple", () => {
      const stacktrace = erlangStacktrace(
        "tuple_size",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a tuple")]]),
      );
    });

    it("erlang unique_integer: not a list", () => {
      const stacktrace = erlangStacktrace(
        "unique_integer",
        Type.list([Type.atom("bad")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a list")]]),
      );
    });

    it("erlang unique_integer: invalid modifier", () => {
      const stacktrace = erlangStacktrace(
        "unique_integer",
        Type.list([Type.list([Type.atom("bad")])]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("invalid modifier")]]),
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

    it("error frame carries args", () => {
      const stacktrace = Type.list();

      let caught;

      try {
        format_error(Type.atom("badarg"), stacktrace);
      } catch (e) {
        caught = e;
      }

      assert.deepStrictEqual(caught.stacktrace, [
        {
          module: "erl_erts_errors",
          function: "format_error",
          arityOrArgs: Type.list([Type.atom("badarg"), stacktrace]),
          file: null,
          line: null,
          errorInfo: null,
        },
      ]);
    });
  });
});
