"use strict";

import {
  assert,
  assertBoxedError,
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
