"use strict";

import {
  assert,
  assertBoxedError,
  buildFunctionClauseErrorMsg,
  contextFixture,
  defineRuntimeGlobals,
} from "../support/helpers.mjs";

import Erlang_Binary from "../../../assets/js/erlang/binary.mjs";
import Erlang_Erl_Stdlib_Errors from "../../../assets/js/erlang/erl_stdlib_errors.mjs";
import Erlang_Re from "../../../assets/js/erlang/re.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

const errorInfo = Type.keywordList([
  [
    Type.atom("error_info"),
    Type.map([[Type.atom("module"), Type.atom("erl_stdlib_errors")]]),
  ],
]);

const badoptErrorInfo = Type.keywordList([
  [
    Type.atom("error_info"),
    Type.map([
      [Type.atom("cause"), Type.atom("badopt")],
      [Type.atom("module"), Type.atom("erl_stdlib_errors")],
    ]),
  ],
]);

function binaryStacktrace(functionName, argsOrArity, location = errorInfo) {
  return Type.list([
    Type.tuple([
      Type.atom("binary"),
      Type.atom(functionName),
      argsOrArity,
      location,
    ]),
  ]);
}

function listsStacktrace(functionName, argsOrArity) {
  return Type.list([
    Type.tuple([
      Type.atom("lists"),
      Type.atom(functionName),
      argsOrArity,
      errorInfo,
    ]),
  ]);
}

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

function mathStacktrace(functionName, argsOrArity) {
  return Type.list([
    Type.tuple([
      Type.atom("math"),
      Type.atom(functionName),
      argsOrArity,
      errorInfo,
    ]),
  ]);
}

function reStacktrace(functionName, argsOrArity, location = errorInfo) {
  return Type.list([
    Type.tuple([
      Type.atom("re"),
      Type.atom(functionName),
      argsOrArity,
      location,
    ]),
  ]);
}

function unicodeStacktrace(functionName, argsOrArity) {
  return Type.list([
    Type.tuple([
      Type.atom("unicode"),
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

    it("binary at: bad position", () => {
      const stacktrace = binaryStacktrace(
        "at",
        Type.list([Type.bitstring("abc"), Type.atom("x")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not an integer")]]),
      );
    });

    it("binary at: negative position", () => {
      const stacktrace = binaryStacktrace(
        "at",
        Type.list([Type.bitstring("abc"), Type.integer(-1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("out of range")]]),
      );
    });

    it("binary at: bitstring subject", () => {
      const stacktrace = binaryStacktrace(
        "at",
        Type.list([Type.bitstring([1]), Type.integer(0)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("is a bitstring (expected a binary)"),
          ],
        ]),
      );
    });

    it("binary at: valid arguments produce no fragments", () => {
      const stacktrace = binaryStacktrace(
        "at",
        Type.list([Type.bitstring("abc"), Type.integer(10)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("binary compile_pattern: not a valid pattern", () => {
      const stacktrace = binaryStacktrace(
        "compile_pattern",
        Type.list([Type.bitstring("")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a valid pattern")]]),
      );
    });

    it("binary copy: bad subject and count", () => {
      const stacktrace = binaryStacktrace(
        "copy",
        Type.list([Type.atom("x"), Type.integer(-1)]),
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

    it("binary first: empty binary", () => {
      const stacktrace = binaryStacktrace(
        "first",
        Type.list([Type.bitstring("")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("a zero-sized binary is not allowed"),
          ],
        ]),
      );
    });

    it("binary first: not a binary", () => {
      const stacktrace = binaryStacktrace("first", Type.list([Type.atom("x")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a binary")]]),
      );
    });

    it("binary last: empty binary", () => {
      const stacktrace = binaryStacktrace(
        "last",
        Type.list([Type.bitstring("")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("a zero-sized binary is not allowed"),
          ],
        ]),
      );
    });

    it("binary match/2: bad subject and pattern", () => {
      const stacktrace = binaryStacktrace(
        "match",
        Type.list([Type.atom("x"), Type.atom("y")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not a binary")],
          [Type.integer(2), Type.bitstring("not a valid pattern")],
        ]),
      );
    });

    it("binary match/2: empty binary pattern", () => {
      const stacktrace = binaryStacktrace(
        "match",
        Type.list([Type.bitstring("abc"), Type.bitstring("")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a valid pattern")]]),
      );
    });

    it("binary match/2: compiled pattern is valid", () => {
      const compiledPattern = Erlang_Binary["compile_pattern/1"](
        Type.bitstring("b"),
      );

      const stacktrace = binaryStacktrace(
        "match",
        Type.list([Type.bitstring("abc"), compiledPattern]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("binary match/3: scope not wholly inside binary", () => {
      const scopeOption = Type.tuple([
        Type.atom("scope"),
        Type.tuple([Type.integer(0), Type.integer(10)]),
      ]);

      const stacktrace = binaryStacktrace(
        "match",
        Type.list([
          Type.bitstring("abc"),
          Type.bitstring("b"),
          Type.list([scopeOption]),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(3),
            Type.bitstring("specified part is not wholly inside binary"),
          ],
        ]),
      );
    });

    it("binary match/3: bad options", () => {
      const stacktrace = binaryStacktrace(
        "match",
        Type.list([
          Type.bitstring("abc"),
          Type.bitstring("b"),
          Type.list([Type.atom("x")]),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(3), Type.bitstring("invalid options")]]),
      );
    });

    it("binary matches: delegates to the match clauses", () => {
      const stacktrace = binaryStacktrace(
        "matches",
        Type.list([Type.bitstring("abc"), Type.bitstring("")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a valid pattern")]]),
      );
    });

    it("binary replace/3: bad replacement", () => {
      const stacktrace = binaryStacktrace(
        "replace",
        Type.list([Type.bitstring("abc"), Type.bitstring("b"), Type.atom("x")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(3), Type.bitstring("not a valid replacement")],
        ]),
      );
    });

    it("binary replace/4: badopt cause adds the options fragment", () => {
      const stacktrace = binaryStacktrace(
        "replace",
        Type.list([
          Type.bitstring("abc"),
          Type.bitstring("b"),
          Type.bitstring("x"),
          Type.list([Type.atom("y")]),
        ]),
        badoptErrorInfo,
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(4), Type.bitstring("invalid options")]]),
      );
    });

    it("binary replace/4: bad replacement with badopt cause", () => {
      const stacktrace = binaryStacktrace(
        "replace",
        Type.list([
          Type.bitstring("abc"),
          Type.bitstring("b"),
          Type.atom("x"),
          Type.list([Type.atom("y")]),
        ]),
        badoptErrorInfo,
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(3), Type.bitstring("not a valid replacement")],
          [Type.integer(4), Type.bitstring("invalid options")],
        ]),
      );
    });

    it("binary replace/4: valid arguments without cause blame the options", () => {
      const stacktrace = binaryStacktrace(
        "replace",
        Type.list([
          Type.bitstring("abc"),
          Type.bitstring("b"),
          Type.bitstring("x"),
          Type.list([Type.atom("y")]),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(4), Type.bitstring("invalid options")]]),
      );
    });

    it("binary split/2: bad pattern", () => {
      const stacktrace = binaryStacktrace(
        "split",
        Type.list([Type.bitstring("abc"), Type.atom("x")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a valid pattern")]]),
      );
    });

    it("binary split/3: bad options", () => {
      const stacktrace = binaryStacktrace(
        "split",
        Type.list([
          Type.bitstring("abc"),
          Type.bitstring("b"),
          Type.list([Type.atom("x")]),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(3), Type.bitstring("invalid options")]]),
      );
    });

    it("lists keyfind: bad position", () => {
      const stacktrace = listsStacktrace(
        "keyfind",
        Type.list([
          Type.atom("k"),
          Type.atom("bad"),
          Type.list([Type.tuple([Type.atom("k"), Type.integer(1)])]),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not an integer")]]),
      );
    });

    it("lists keyfind: position out of range", () => {
      const stacktrace = listsStacktrace(
        "keyfind",
        Type.list([
          Type.atom("k"),
          Type.integer(0),
          Type.list([Type.tuple([Type.atom("k"), Type.integer(1)])]),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("out of range")]]),
      );
    });

    it("lists keyfind: not a list", () => {
      const stacktrace = listsStacktrace(
        "keyfind",
        Type.list([Type.atom("k"), Type.integer(1), Type.atom("bad")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(3), Type.bitstring("not a list")]]),
      );
    });

    it("lists keyfind: improper list", () => {
      const stacktrace = listsStacktrace(
        "keyfind",
        Type.list([
          Type.atom("k"),
          Type.integer(1),
          Type.improperList([
            Type.tuple([Type.atom("k"), Type.integer(1)]),
            Type.atom("tail"),
          ]),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(3), Type.bitstring("not a proper list")]]),
      );
    });

    it("lists keyfind: bad position and bad list", () => {
      const stacktrace = listsStacktrace(
        "keyfind",
        Type.list([Type.atom("k"), Type.integer(0), Type.atom("bad")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(2), Type.bitstring("out of range")],
          [Type.integer(3), Type.bitstring("not a list")],
        ]),
      );
    });

    it("lists keymember delegates to the keyfind clause", () => {
      const stacktrace = listsStacktrace(
        "keymember",
        Type.list([
          Type.atom("k"),
          Type.atom("bad"),
          Type.list([Type.tuple([Type.atom("k"), Type.integer(1)])]),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not an integer")]]),
      );
    });

    it("lists keysearch delegates to the keyfind clause", () => {
      const stacktrace = listsStacktrace(
        "keysearch",
        Type.list([
          Type.atom("k"),
          Type.atom("bad"),
          Type.list([Type.tuple([Type.atom("k"), Type.integer(1)])]),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not an integer")]]),
      );
    });

    it("lists member: not a list", () => {
      const stacktrace = listsStacktrace(
        "member",
        Type.list([Type.integer(1), Type.atom("bad")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a list")]]),
      );
    });

    it("lists member: improper list", () => {
      const stacktrace = listsStacktrace(
        "member",
        Type.list([
          Type.integer(5),
          Type.improperList([Type.integer(1), Type.integer(2)]),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a proper list")]]),
      );
    });

    it("lists reverse: not a list", () => {
      const stacktrace = listsStacktrace(
        "reverse",
        Type.list([Type.atom("bad"), Type.list()]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a list")]]),
      );
    });

    it("lists reverse: improper list", () => {
      const stacktrace = listsStacktrace(
        "reverse",
        Type.list([
          Type.improperList([Type.integer(1), Type.integer(2)]),
          Type.list(),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a proper list")]]),
      );
    });

    it("lists seq: non-integer arguments", () => {
      const stacktrace = listsStacktrace(
        "seq",
        Type.list([Type.atom("a"), Type.atom("b"), Type.atom("c")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not an integer")],
          [Type.integer(2), Type.bitstring("not an integer")],
          [Type.integer(3), Type.bitstring("not an integer")],
        ]),
      );
    });

    it("lists seq: zero increment", () => {
      const stacktrace = listsStacktrace(
        "seq",
        Type.list([Type.integer(1), Type.integer(10), Type.integer(0)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(3), Type.bitstring("not a positive increment")],
        ]),
      );
    });

    it("lists seq: wrong positive increment", () => {
      const stacktrace = listsStacktrace(
        "seq",
        Type.list([Type.integer(10), Type.integer(1), Type.integer(1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(3), Type.bitstring("not a negative increment")],
        ]),
      );
    });

    it("lists seq: wrong negative increment", () => {
      const stacktrace = listsStacktrace(
        "seq",
        Type.list([Type.integer(1), Type.integer(10), Type.integer(-1)]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(3), Type.bitstring("not a positive increment")],
        ]),
      );
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

    it("math ceil: not a number", () => {
      const stacktrace = mathStacktrace("ceil", Type.list([Type.atom("a")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a number")]]),
      );
    });

    it("math log: domain error", () => {
      const stacktrace = mathStacktrace("log", Type.list([Type.integer(0)]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("is outside the domain for this function"),
          ],
        ]),
      );
    });

    it("math log: not a number", () => {
      const stacktrace = mathStacktrace("log", Type.list([Type.atom("a")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a number")]]),
      );
    });

    it("math pow: both arguments not numbers", () => {
      const stacktrace = mathStacktrace(
        "pow",
        Type.list([Type.atom("a"), Type.atom("b")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not a number")],
          [Type.integer(2), Type.bitstring("not a number")],
        ]),
      );
    });

    it("math pow: valid number skips its fragment", () => {
      const stacktrace = mathStacktrace(
        "pow",
        Type.list([Type.integer(7), Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a number")]]),
      );
    });

    it("math unknown functions fall to the argument-count clauses", () => {
      const stacktrace = mathStacktrace("unknown", Type.list([Type.atom("a")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not a number")]]),
      );
    });

    it("re compile/1: not an iodata term", () => {
      const stacktrace = reStacktrace("compile", Type.list([Type.atom("abc")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not an iodata term")]]),
      );
    });

    it("re compile/2: parse-error pattern", () => {
      const stacktrace = reStacktrace(
        "compile",
        Type.list([Type.bitstring("a("), Type.list()]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring(
              "could not parse regular expression\nmissing closing parenthesis on character 2",
            ),
          ],
        ]),
      );
    });

    it("re compile/2: valid pattern with badopt cause", () => {
      const stacktrace = reStacktrace(
        "compile",
        Type.list([Type.bitstring("abc"), Type.list([Type.atom("bad")])]),
        badoptErrorInfo,
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("invalid options")]]),
      );
    });

    it("re compile/2: parse-error pattern with badopt cause", () => {
      const stacktrace = reStacktrace(
        "compile",
        Type.list([Type.bitstring("a("), Type.list([Type.atom("bad")])]),
        badoptErrorInfo,
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring(
              "could not parse regular expression\nmissing closing parenthesis on character 2",
            ),
          ],
          [Type.integer(2), Type.bitstring("invalid options")],
        ]),
      );
    });

    it("re compile/2: non-iodata pattern with badopt cause", () => {
      const stacktrace = reStacktrace(
        "compile",
        Type.list([Type.atom("abc"), Type.list([Type.atom("bad")])]),
        badoptErrorInfo,
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not an iodata term")],
          [Type.integer(2), Type.bitstring("invalid options")],
        ]),
      );
    });

    it("re import: not an exported regular expression", () => {
      const stacktrace = reStacktrace("import", Type.list([Type.atom("abc")]));

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not an exported regular expression"),
          ],
        ]),
      );
    });

    it("re inspect: not a compiled regular expression", () => {
      const stacktrace = reStacktrace(
        "inspect",
        Type.list([Type.atom("abc"), Type.atom("namelist")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not a compiled regular expression"),
          ],
        ]),
      );
    });

    it("re inspect: bad item", () => {
      const compiledPattern = Erlang_Re["compile/1"](Type.bitstring("a"))
        .data[1];

      const stacktrace = reStacktrace(
        "inspect",
        Type.list([compiledPattern, Type.atom("bad_item")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("not a valid item")]]),
      );
    });

    it("re inspect: non-atom item with a non-compiled first argument", () => {
      const stacktrace = reStacktrace(
        "inspect",
        Type.list([Type.atom("abc"), Type.bitstring("namelist")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not a compiled regular expression"),
          ],
          [Type.integer(2), Type.bitstring("not a valid item")],
        ]),
      );
    });

    it("re run/2: bad subject and pattern", () => {
      const stacktrace = reStacktrace(
        "run",
        Type.list([Type.atom("abc"), Type.atom("bad")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not an iodata term")],
          [
            Type.integer(2),
            Type.bitstring(
              "neither an iodata term nor a compiled regular expression",
            ),
          ],
        ]),
      );
    });

    it("re run/2: parse-error pattern", () => {
      const stacktrace = reStacktrace(
        "run",
        Type.list([Type.bitstring("abc"), Type.bitstring("a(")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(2),
            Type.bitstring(
              "could not parse regular expression\nmissing closing parenthesis on character 2",
            ),
          ],
        ]),
      );
    });

    it("re run/2: compiled pattern is valid", () => {
      const compiledPattern = Erlang_Re["compile/1"](Type.bitstring("a"))
        .data[1];

      const stacktrace = reStacktrace(
        "run",
        Type.list([Type.bitstring("abc"), compiledPattern]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("re run/2: fake compiled pattern tuple", () => {
      const fakePattern = Type.tuple([
        Type.atom("re_pattern"),
        Type.integer(0),
        Type.integer(0),
        Type.integer(0),
        Type.atom("fake"),
      ]);

      const stacktrace = reStacktrace(
        "run",
        Type.list([Type.bitstring("abc"), fakePattern]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(2),
            Type.bitstring(
              "neither an iodata term nor a compiled regular expression",
            ),
          ],
        ]),
      );
    });

    it("re run/2: improper iolist subject with binary tail is valid", () => {
      const subject = Type.improperList([
        Type.integer(97),
        Type.bitstring("b"),
      ]);

      const stacktrace = reStacktrace(
        "run",
        Type.list([subject, Type.bitstring("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("re run/2: improper iolist subject with non-binary tail", () => {
      const subject = Type.improperList([Type.integer(97), Type.integer(98)]);

      const stacktrace = reStacktrace(
        "run",
        Type.list([subject, Type.bitstring("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not an iodata term")]]),
      );
    });

    it("re run/2: iolist subject with out-of-range integer", () => {
      const subject = Type.list([Type.integer(256)]);

      const stacktrace = reStacktrace(
        "run",
        Type.list([subject, Type.bitstring("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(1), Type.bitstring("not an iodata term")]]),
      );
    });

    it("re run/3: valid arguments with badopt cause", () => {
      const stacktrace = reStacktrace(
        "run",
        Type.list([
          Type.bitstring("abc"),
          Type.bitstring("a"),
          Type.list([Type.atom("bad")]),
        ]),
        badoptErrorInfo,
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(3), Type.bitstring("invalid options")]]),
      );
    });

    it("re run/3: bad subject and pattern with badopt cause", () => {
      const stacktrace = reStacktrace(
        "run",
        Type.list([
          Type.atom("abc"),
          Type.atom("bad"),
          Type.list([Type.atom("x")]),
        ]),
        badoptErrorInfo,
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("not an iodata term")],
          [
            Type.integer(2),
            Type.bitstring(
              "neither an iodata term nor a compiled regular expression",
            ),
          ],
          [Type.integer(3), Type.bitstring("invalid options")],
        ]),
      );
    });

    it("re run/3: valid arguments produce no fragments", () => {
      const stacktrace = reStacktrace(
        "run",
        Type.list([
          Type.bitstring("abc"),
          Type.bitstring("a"),
          Type.list([Type.atom("caseless")]),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("unicode characters_to_binary/1: bad chardata", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_binary",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not valid character data (an iodata term)"),
          ],
        ]),
      );
    });

    it("unicode characters_to_binary/2: bad chardata and encoding", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_binary",
        Type.list([Type.atom("a"), Type.atom("foo")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not valid character data (an iodata term)"),
          ],
          [Type.integer(2), Type.bitstring("not a valid encoding")],
        ]),
      );
    });

    it("unicode characters_to_binary/3: bad chardata with valid encodings", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_binary",
        Type.list([Type.atom("a"), Type.atom("utf8"), Type.atom("utf8")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not valid character data (an iodata term)"),
          ],
        ]),
      );
    });

    it("unicode characters_to_binary/3: bad encodings", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_binary",
        Type.list([Type.bitstring("abc"), Type.atom("foo"), Type.atom("bar")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(2), Type.bitstring("not a valid encoding")],
          [Type.integer(3), Type.bitstring("not a valid encoding")],
        ]),
      );
    });

    it("unicode characters_to_binary/3: endianness tuple encodings are valid", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_binary",
        Type.list([
          Type.bitstring("abc"),
          Type.tuple([Type.atom("utf16"), Type.atom("big")]),
          Type.tuple([Type.atom("utf32"), Type.atom("little")]),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("unicode characters_to_binary/3: latin1 and unicode encodings are valid", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_binary",
        Type.list([
          Type.bitstring("abc"),
          Type.atom("latin1"),
          Type.atom("unicode"),
        ]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(result, Type.map());
    });

    it("unicode characters_to_list delegates to the characters_to_binary clauses", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_list",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not valid character data (an iodata term)"),
          ],
        ]),
      );
    });

    it("unicode characters_to_nfc_binary: bad chardata", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_nfc_binary",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not valid character data (an iodata term)"),
          ],
        ]),
      );
    });

    it("unicode characters_to_nfc_list: bad chardata", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_nfc_list",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not valid character data (an iodata term)"),
          ],
        ]),
      );
    });

    it("unicode characters_to_nfd_binary: bad chardata", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_nfd_binary",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not valid character data (an iodata term)"),
          ],
        ]),
      );
    });

    it("unicode characters_to_nfd_list: bad chardata", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_nfd_list",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not valid character data (an iodata term)"),
          ],
        ]),
      );
    });

    it("unicode characters_to_nfkc_binary: bad chardata", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_nfkc_binary",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not valid character data (an iodata term)"),
          ],
        ]),
      );
    });

    it("unicode characters_to_nfkc_list: bad chardata", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_nfkc_list",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not valid character data (an iodata term)"),
          ],
        ]),
      );
    });

    it("unicode characters_to_nfkd_binary: bad chardata", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_nfkd_binary",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not valid character data (an iodata term)"),
          ],
        ]),
      );
    });

    it("unicode characters_to_nfkd_list: bad chardata", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_nfkd_list",
        Type.list([Type.atom("a")]),
      );

      const result = format_error(Type.atom("badarg"), stacktrace);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.integer(1),
            Type.bitstring("not valid character data (an iodata term)"),
          ],
        ]),
      );
    });

    it("raises FunctionClauseError when the stacktrace is empty", () => {
      const stacktrace = Type.list();

      assertBoxedError(
        () => format_error(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg(":erl_stdlib_errors.format_error/2", [
          Type.atom("badarg"),
          stacktrace,
        ]),
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
        buildFunctionClauseErrorMsg(":erl_stdlib_errors.format_error/2", [
          Type.atom("badarg"),
          stacktrace,
        ]),
      );
    });

    it("raises FunctionClauseError when a binary clause needs args but the frame carries an arity", () => {
      const stacktrace = binaryStacktrace("at", Type.integer(2));

      assertBoxedError(
        () => format_error(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg(
          ":erl_stdlib_errors.format_binary_error/3",
          [Type.atom("at"), Type.integer(2), Type.atom("none")],
        ),
      );
    });

    it("raises FunctionClauseError when matches delegates a frame that carries an arity", () => {
      const stacktrace = binaryStacktrace("matches", Type.integer(2));

      assertBoxedError(
        () => format_error(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg(
          ":erl_stdlib_errors.format_binary_error/3",
          [Type.atom("match"), Type.integer(2), Type.atom("none")],
        ),
      );
    });

    it("raises FunctionClauseError for an unknown lists function", () => {
      const fun = Type.atom("zip");
      const args = Type.list([Type.list(), Type.list()]);

      assertBoxedError(
        () => format_error(Type.atom("badarg"), listsStacktrace("zip", args)),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg(":erl_stdlib_errors.format_lists_error/2", [
          fun,
          args,
        ]),
      );
    });

    it("raises FunctionClauseError when a lists clause needs args but the frame carries an arity", () => {
      const fun = Type.atom("keyfind");
      const arity = Type.integer(3);

      assertBoxedError(
        () =>
          format_error(Type.atom("badarg"), listsStacktrace("keyfind", arity)),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg(":erl_stdlib_errors.format_lists_error/2", [
          fun,
          arity,
        ]),
      );
    });

    it("raises FunctionClauseError when a maps clause needs args but the frame carries an arity", () => {
      const stacktrace = mapsStacktrace("get", Type.integer(2));

      assertBoxedError(
        () => format_error(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg(":erl_stdlib_errors.format_maps_error/2", [
          Type.atom("get"),
          Type.integer(2),
        ]),
      );
    });

    it("raises FunctionClauseError when a math clause needs args but the frame carries an arity", () => {
      const stacktrace = mathStacktrace("ceil", Type.integer(1));

      assertBoxedError(
        () => format_error(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg(":erl_stdlib_errors.format_math_error/2", [
          Type.atom("ceil"),
          Type.integer(1),
        ]),
      );
    });

    it("raises FunctionClauseError when a math domain-error clause needs args but the frame carries an arity", () => {
      const stacktrace = mathStacktrace("log", Type.integer(1));

      assertBoxedError(
        () => format_error(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg(":erl_stdlib_errors.maybe_domain_error/1", [
          Type.integer(1),
        ]),
      );
    });

    it("raises FunctionClauseError for an unknown re function", () => {
      const fun = Type.atom("version");
      const args = Type.list();

      assertBoxedError(
        () => format_error(Type.atom("badarg"), reStacktrace("version", args)),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg(":erl_stdlib_errors.format_re_error/3", [
          fun,
          args,
          Type.atom("none"),
        ]),
      );
    });

    it("raises FunctionClauseError when a re clause needs args but the frame carries an arity", () => {
      const stacktrace = reStacktrace("run", Type.integer(2));

      assertBoxedError(
        () => format_error(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg(":erl_stdlib_errors.format_re_error/3", [
          Type.atom("run"),
          Type.integer(2),
          Type.atom("none"),
        ]),
      );
    });

    it("raises FunctionClauseError when a unicode clause needs args but the frame carries an arity", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_nfc_binary",
        Type.integer(1),
      );

      assertBoxedError(
        () => format_error(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg(
          ":erl_stdlib_errors.format_unicode_error/2",
          [Type.atom("characters_to_nfc_binary"), Type.integer(1)],
        ),
      );
    });

    it("raises FunctionClauseError when characters_to_list delegates a frame that carries an arity", () => {
      const stacktrace = unicodeStacktrace(
        "characters_to_list",
        Type.integer(1),
      );

      assertBoxedError(
        () => format_error(Type.atom("badarg"), stacktrace),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg(
          ":erl_stdlib_errors.format_unicode_error/2",
          [Type.atom("characters_to_binary"), Type.integer(1)],
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
          module: "erl_stdlib_errors",
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
