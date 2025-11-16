"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedFalse,
  assertBoxedStrictEqual,
  assertBoxedTrue,
  contextFixture,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang from "../../../assets/js/erlang/erlang.mjs";
import HologramInterpreterError from "../../../assets/js/errors/interpreter_error.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const atomA = Type.atom("a");
const atomAbc = Type.atom("abc");
const atomB = Type.atom("b");
const float1 = Type.float(1.0);
const float2 = Type.float(2.0);
const float3 = Type.float(3.0);
const float6 = Type.float(6.0);
const integer1 = Type.integer(1);
const integer2 = Type.integer(2);
const integer3 = Type.integer(3);
const integer6 = Type.integer(6);
const list1 = Type.list([integer1, integer2]);
const pid1 = Type.pid("my_node@my_host", [0, 11, 111]);
const pid2 = Type.pid("my_node@my_host", [0, 11, 112]);
const tuple2 = Type.tuple([Type.integer(1), Type.integer(2)]);
const tuple3 = Type.tuple([Type.integer(1), Type.integer(2), Type.integer(3)]);

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/erlang_test.exs
// Always update both together.

describe("Erlang", () => {
  describe("*/2", () => {
    const testedFun = Erlang["*/2"];

    it("float * float", () => {
      assert.deepStrictEqual(testedFun(float2, float3), float6);
    });

    it("float * integer", () => {
      assert.deepStrictEqual(testedFun(float3, integer2), float6);
    });

    it("integer * float", () => {
      assert.deepStrictEqual(testedFun(integer2, float3), float6);
    });

    it("integer * integer", () => {
      assert.deepStrictEqual(testedFun(integer2, integer3), integer6);
    });

    it("raises ArithmeticError if the first argument is not a number", () => {
      assertBoxedError(
        () => testedFun(atomA, integer1),
        "ArithmeticError",
        "bad argument in arithmetic expression: :a * 1",
      );
    });

    it("raises ArithmeticError if the second argument is not a number", () => {
      assertBoxedError(
        () => testedFun(integer1, atomA),
        "ArithmeticError",
        "bad argument in arithmetic expression: 1 * :a",
      );
    });
  });

  describe("+/1", () => {
    const testedFun = Erlang["+/1"];

    it("positive float", () => {
      assert.deepStrictEqual(testedFun(Type.float(1.23)), Type.float(1.23));
    });

    it("positive integer", () => {
      assert.deepStrictEqual(testedFun(Type.integer(123)), Type.integer(123));
    });

    it("negative float", () => {
      assert.deepStrictEqual(testedFun(Type.float(-1.23)), Type.float(-1.23));
    });

    it("negative integer", () => {
      assert.deepStrictEqual(testedFun(Type.integer(-123)), Type.integer(-123));
    });

    it("0.0 (float)", () => {
      assert.deepStrictEqual(testedFun(Type.float(0.0)), Type.float(0.0));
    });

    it("0 (integer)", () => {
      assert.deepStrictEqual(testedFun(Type.integer(0)), Type.integer(0));
    });

    it("non-number", () => {
      assertBoxedError(
        () => testedFun(atomAbc),
        "ArithmeticError",
        "bad argument in arithmetic expression: +(:abc)",
      );
    });
  });

  describe("+/2", () => {
    const testedFun = Erlang["+/2"];

    it("float + float", () => {
      assert.deepStrictEqual(testedFun(float1, float2), float3);
    });

    it("float + integer", () => {
      assert.deepStrictEqual(testedFun(float1, integer2), float3);
    });

    it("integer + float", () => {
      assert.deepStrictEqual(testedFun(integer1, float2), float3);
    });

    it("integer + integer", () => {
      assert.deepStrictEqual(testedFun(integer1, integer2), integer3);
    });

    it("raises ArithmeticError if the first argument is not a number", () => {
      assertBoxedError(
        () => testedFun(atomA, integer1),
        "ArithmeticError",
        "bad argument in arithmetic expression: :a + 1",
      );
    });

    it("raises ArithmeticError if the second argument is not a number", () => {
      assertBoxedError(
        () => testedFun(integer1, atomA),
        "ArithmeticError",
        "bad argument in arithmetic expression: 1 + :a",
      );
    });
  });

  describe("++/2", () => {
    const testedFun = Erlang["++/2"];

    it("concatenates a proper non-empty list and another proper non-empty list", () => {
      const left = Type.list([Type.integer(1), Type.integer(2)]);
      const right = Type.list([Type.integer(3), Type.integer(4)]);

      const result = testedFun(left, right);

      const expected = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("concatenates a proper non-empty list and an improper list", () => {
      const left = Type.list([Type.integer(1), Type.integer(2)]);
      const right = Type.improperList([Type.integer(3), Type.integer(4)]);

      const result = testedFun(left, right);

      const expected = Type.improperList([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("concatenates a proper non-empty list and a term that is not a list", () => {
      const left = Type.list([Type.integer(1), Type.integer(2)]);
      const right = Type.integer(3);

      const result = testedFun(left, right);

      const expected = Type.improperList([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("first list is empty", () => {
      const left = Type.list();
      const right = Type.list([Type.integer(1), Type.integer(2)]);

      const result = testedFun(left, right);
      const expected = Type.list([Type.integer(1), Type.integer(2)]);

      assert.deepStrictEqual(result, expected);
    });

    it("second list is empty", () => {
      const left = Type.list([Type.integer(1), Type.integer(2)]);
      const right = Type.list();

      const result = testedFun(left, right);
      const expected = Type.list([Type.integer(1), Type.integer(2)]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises ArgumentError if the first argument is not a list", () => {
      assertBoxedError(
        () => testedFun(atomAbc, Type.list()),
        "ArgumentError",
        "argument error",
      );
    });

    it("raises ArgumentError if the first argument is an improper list", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.improperList([Type.integer(1), Type.integer(2)]),
            Type.list(),
          ),
        "ArgumentError",
        "argument error",
      );
    });
  });

  describe("-/1", () => {
    const testedFun = Erlang["-/1"];

    it("positive float", () => {
      assert.deepStrictEqual(testedFun(Type.float(1.23)), Type.float(-1.23));
    });

    it("positive integer", () => {
      assert.deepStrictEqual(testedFun(Type.integer(123)), Type.integer(-123));
    });

    it("negative float", () => {
      assert.deepStrictEqual(testedFun(Type.float(-1.23)), Type.float(1.23));
    });

    it("negative integer", () => {
      assert.deepStrictEqual(testedFun(Type.integer(-123)), Type.integer(123));
    });

    it("0.0 (float)", () => {
      assert.deepStrictEqual(testedFun(Type.float(0.0)), Type.float(0.0));
    });

    it("0 (integer)", () => {
      assert.deepStrictEqual(testedFun(Type.integer(0)), Type.integer(0));
    });

    it("non-number", () => {
      assertBoxedError(
        () => testedFun(atomAbc),
        "ArithmeticError",
        "bad argument in arithmetic expression: -(:abc)",
      );
    });
  });

  describe("-/2", () => {
    const testedFun = Erlang["-/2"];

    it("float - float", () => {
      assert.deepStrictEqual(testedFun(float3, float2), float1);
    });

    it("float - integer", () => {
      assert.deepStrictEqual(testedFun(float3, integer2), float1);
    });

    it("integer - float", () => {
      assert.deepStrictEqual(testedFun(integer3, float2), float1);
    });

    it("integer - integer", () => {
      assert.deepStrictEqual(testedFun(integer3, integer2), integer1);
    });

    it("raises ArithmeticError if the first argument is not a number", () => {
      assertBoxedError(
        () => testedFun(atomA, integer1),
        "ArithmeticError",
        "bad argument in arithmetic expression: :a - 1",
      );
    });

    it("raises ArithmeticError if the second argument is not a number", () => {
      assertBoxedError(
        () => testedFun(integer1, atomA),
        "ArithmeticError",
        "bad argument in arithmetic expression: 1 - :a",
      );
    });
  });

  describe("--/2", () => {
    const testedFun = Erlang["--/2"];

    it("there are no matching elems", () => {
      const left = Type.list([Type.integer(1), Type.integer(2)]);
      const right = Type.list([Type.integer(3), Type.integer(4)]);

      assert.deepStrictEqual(testedFun(left, right), left);
    });

    it("removes the first occurrence of an element in the left list for each element in the right list", () => {
      const left = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(1),
      ]);

      const right = Type.list([
        Type.integer(1),
        Type.integer(3),
        Type.integer(3),
        Type.integer(4),
      ]);

      const expected = Type.list([
        Type.integer(2),
        Type.integer(1),
        Type.integer(2),
        Type.integer(1),
      ]);

      assert.deepStrictEqual(testedFun(left, right), expected);
    });

    it("first list is empty", () => {
      const left = Type.list();
      const right = Type.list([Type.integer(1), Type.integer(2)]);

      assert.deepStrictEqual(testedFun(left, right), left);
    });

    it("second list is empty", () => {
      const left = Type.list([Type.integer(1), Type.integer(2)]);
      const right = Type.list();

      assert.deepStrictEqual(testedFun(left, right), left);
    });

    it("first arg is not a list", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.atom("abc"),
            Type.list([Type.integer(1), Type.integer(2)]),
          ),
        "ArgumentError",
        "argument error",
      );
    });

    it("second arg is not a list", () => {
      assertBoxedError(
        () =>
          testedFun(
            Type.list([Type.integer(1), Type.integer(2)]),
            Type.atom("abc"),
          ),
        "ArgumentError",
        "argument error",
      );
    });
  });

  describe("//2", () => {
    const testedFun = Erlang["//2"];

    it("divides float by float", () => {
      assert.deepStrictEqual(
        testedFun(Type.float(3.0), Type.float(2.0)),
        Type.float(1.5),
      );
    });

    it("divides integer by integer", () => {
      assert.deepStrictEqual(
        testedFun(Type.integer(3), Type.integer(2)),
        Type.float(1.5),
      );
    });

    it("first arg is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.integer(3)),
        "ArithmeticError",
        "bad argument in arithmetic expression: :abc / 3",
      );
    });

    it("second arg is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.integer(3), Type.atom("abc")),
        "ArithmeticError",
        "bad argument in arithmetic expression: 3 / :abc",
      );
    });

    it("second arg is equal to (float) 0.0", () => {
      assertBoxedError(
        () => testedFun(Type.integer(1), Type.float(0.0)),
        "ArithmeticError",
        "bad argument in arithmetic expression: 1 / 0.0",
      );
    });

    it("second arg is equal to (integer) 0", () => {
      assertBoxedError(
        () => testedFun(Type.integer(1), Type.integer(0)),
        "ArithmeticError",
        "bad argument in arithmetic expression: 1 / 0",
      );
    });
  });

  describe("/=/2", () => {
    const testedFun = Erlang["/=/2"];

    it("atom == atom", () => {
      assertBoxedFalse(testedFun(atomA, atomA));
    });

    it("float == float", () => {
      assertBoxedFalse(testedFun(float1, float1));
    });

    it("float == integer", () => {
      assertBoxedFalse(testedFun(float1, integer1));
    });

    it("integer == float", () => {
      assertBoxedFalse(testedFun(integer1, float1));
    });

    it("integer == integer", () => {
      assertBoxedFalse(testedFun(integer1, integer1));
    });

    it("pid == pid", () => {
      assertBoxedFalse(testedFun(pid1, pid1));
    });

    it("tuple == tuple", () => {
      assertBoxedFalse(testedFun(tuple3, tuple3));
    });

    it("atom < atom", () => {
      assertBoxedTrue(testedFun(atomA, atomB));
    });

    it("float < atom (always)", () => {
      assertBoxedTrue(testedFun(float1, atomA));
    });

    it("float < float", () => {
      assertBoxedTrue(testedFun(float1, float2));
    });

    it("float < integer", () => {
      assertBoxedTrue(testedFun(float1, integer2));
    });

    it("integer < atom (always)", () => {
      assertBoxedTrue(testedFun(integer1, atomA));
    });

    it("integer < float", () => {
      assertBoxedTrue(testedFun(integer1, float2));
    });

    it("integer < integer", () => {
      assertBoxedTrue(testedFun(integer1, integer2));
    });

    it("pid < pid", () => {
      assertBoxedTrue(testedFun(pid1, pid2));
    });

    it("pid < tuple (always)", () => {
      assertBoxedTrue(testedFun(pid1, tuple2));
    });

    it("tuple < tuple", () => {
      assertBoxedTrue(testedFun(tuple2, tuple3));
    });

    it("atom > atom", () => {
      assertBoxedTrue(testedFun(atomB, atomA));
    });

    it("float > float", () => {
      assertBoxedTrue(testedFun(float2, float1));
    });

    it("float > integer", () => {
      assertBoxedTrue(testedFun(float2, integer1));
    });

    it("integer > float", () => {
      assertBoxedTrue(testedFun(integer2, float1));
    });

    it("integer > integer", () => {
      assertBoxedTrue(testedFun(integer2, integer1));
    });

    it("pid > pid", () => {
      assertBoxedTrue(testedFun(pid2, pid1));
    });

    it("tuple > tuple", () => {
      assertBoxedTrue(testedFun(tuple3, tuple2));
    });

    // TODO: reference, function, port, map, list, bitstring
  });

  describe("</2", () => {
    const testedFun = Erlang["</2"];

    it("atom == atom", () => {
      assertBoxedFalse(testedFun(atomA, atomA));
    });

    it("float == float", () => {
      assertBoxedFalse(testedFun(float1, float1));
    });

    it("float == integer", () => {
      assertBoxedFalse(testedFun(float1, integer1));
    });

    it("integer == float", () => {
      assertBoxedFalse(testedFun(integer1, float1));
    });

    it("integer == integer", () => {
      assertBoxedFalse(testedFun(integer1, integer1));
    });

    it("pid == pid", () => {
      assertBoxedFalse(testedFun(pid1, pid1));
    });

    it("tuple == tuple", () => {
      assertBoxedFalse(testedFun(tuple3, tuple3));
    });

    it("atom < atom", () => {
      assertBoxedTrue(testedFun(atomA, atomB));
    });

    it("float < atom (always)", () => {
      assertBoxedTrue(testedFun(float1, atomA));
    });

    it("float < float", () => {
      assertBoxedTrue(testedFun(float1, float2));
    });

    it("float < integer", () => {
      assertBoxedTrue(testedFun(float1, integer2));
    });

    it("integer < atom (always)", () => {
      assertBoxedTrue(testedFun(integer1, atomA));
    });

    it("integer < float", () => {
      assertBoxedTrue(testedFun(integer1, float2));
    });

    it("integer < integer", () => {
      assertBoxedTrue(testedFun(integer1, integer2));
    });

    it("pid < pid", () => {
      assertBoxedTrue(testedFun(pid1, pid2));
    });

    it("pid < tuple (always)", () => {
      assertBoxedTrue(testedFun(pid1, tuple3));
    });

    it("tuple < tuple", () => {
      assertBoxedTrue(testedFun(tuple2, tuple3));
    });

    it("atom > atom", () => {
      assertBoxedFalse(testedFun(atomB, atomA));
    });

    it("float > float", () => {
      assertBoxedFalse(testedFun(float2, float1));
    });

    it("float > integer", () => {
      assertBoxedFalse(testedFun(float2, integer1));
    });

    it("integer > float", () => {
      assertBoxedFalse(testedFun(integer2, float1));
    });

    it("integer > integer", () => {
      assertBoxedFalse(testedFun(integer2, integer1));
    });

    it("pid > pid", () => {
      assertBoxedFalse(testedFun(pid2, pid1));
    });

    it("tuple > tuple", () => {
      assertBoxedFalse(testedFun(tuple3, tuple2));
    });

    it("throws a not yet implemented error when the left argument type is not yet supported", () => {
      const expectedMessage =
        "Structural comparison currently supports only atoms, bitstrings, floats, integers, pids and tuples, got: [1, 2]";

      assert.throw(
        () => testedFun(list1, integer1),
        HologramInterpreterError,
        expectedMessage,
      );
    });

    it("throws a not yet implemented error when the right argument type is not yet supported", () => {
      const expectedMessage =
        "Structural comparison currently supports only atoms, bitstrings, floats, integers, pids and tuples, got: [1, 2]";

      assert.throw(
        () => testedFun(integer1, list1),
        HologramInterpreterError,
        expectedMessage,
      );
    });

    // TODO: reference, function, port, map, list, bitstring
  });

  describe("=/=/2", () => {
    const testedFun = Erlang["=/=/2"];

    it("atom == atom", () => {
      assertBoxedFalse(testedFun(atomA, atomA));
    });

    it("float == float", () => {
      assertBoxedFalse(testedFun(float1, float1));
    });

    it("float == integer", () => {
      assertBoxedTrue(testedFun(float1, integer1));
    });

    it("integer == float", () => {
      assertBoxedTrue(testedFun(integer1, float1));
    });

    it("integer == integer", () => {
      assertBoxedFalse(testedFun(integer1, integer1));
    });

    it("pid == pid", () => {
      assertBoxedFalse(testedFun(pid1, pid1));
    });

    it("tuple == tuple", () => {
      assertBoxedFalse(testedFun(tuple3, tuple3));
    });

    it("atom < atom", () => {
      assertBoxedTrue(testedFun(atomA, atomB));
    });

    it("float < atom (always)", () => {
      assertBoxedTrue(testedFun(float1, atomA));
    });

    it("float < float", () => {
      assertBoxedTrue(testedFun(float1, float2));
    });

    it("float < integer", () => {
      assertBoxedTrue(testedFun(float1, integer2));
    });

    it("integer < atom (always)", () => {
      assertBoxedTrue(testedFun(integer1, atomA));
    });

    it("integer < float", () => {
      assertBoxedTrue(testedFun(integer1, float2));
    });

    it("integer < integer", () => {
      assertBoxedTrue(testedFun(integer1, integer2));
    });

    it("pid < pid", () => {
      assertBoxedTrue(testedFun(pid1, pid2));
    });

    it("pid < tuple (always)", () => {
      assertBoxedTrue(testedFun(pid1, tuple3));
    });

    it("tuple < tuple", () => {
      assertBoxedTrue(testedFun(tuple2, tuple3));
    });

    it("atom > atom", () => {
      assertBoxedTrue(testedFun(atomB, atomA));
    });

    it("float > float", () => {
      assertBoxedTrue(testedFun(float2, float1));
    });

    it("float > integer", () => {
      assertBoxedTrue(testedFun(float2, integer1));
    });

    it("integer > float", () => {
      assertBoxedTrue(testedFun(integer2, float1));
    });

    it("integer > integer", () => {
      assertBoxedTrue(testedFun(integer2, integer1));
    });

    it("pid > pid", () => {
      assertBoxedTrue(testedFun(pid2, pid1));
    });

    it("tuple > tuple", () => {
      assertBoxedTrue(testedFun(tuple3, tuple2));
    });

    // TODO: reference, function, port, map, list, bitstring
  });

  describe("=:=/2", () => {
    const testedFun = Erlang["=:=/2"];

    it("atom == atom", () => {
      assertBoxedTrue(testedFun(atomA, atomA));
    });

    it("float == float", () => {
      assertBoxedTrue(testedFun(float1, float1));
    });

    it("float == integer", () => {
      assertBoxedFalse(testedFun(float1, integer1));
    });

    it("integer == float", () => {
      assertBoxedFalse(testedFun(integer1, float1));
    });

    it("integer == integer", () => {
      assertBoxedTrue(testedFun(integer1, integer1));
    });

    it("pid == pid", () => {
      assertBoxedTrue(testedFun(pid1, pid1));
    });

    it("tuple == tuple", () => {
      assertBoxedTrue(testedFun(tuple3, tuple3));
    });

    it("atom < atom", () => {
      assertBoxedFalse(testedFun(atomA, atomB));
    });

    it("float < atom (always)", () => {
      assertBoxedFalse(testedFun(float1, atomA));
    });

    it("float < float", () => {
      assertBoxedFalse(testedFun(float1, float2));
    });

    it("float < integer", () => {
      assertBoxedFalse(testedFun(float1, integer2));
    });

    it("integer < atom (always)", () => {
      assertBoxedFalse(testedFun(integer1, atomA));
    });

    it("integer < float", () => {
      assertBoxedFalse(testedFun(integer1, float2));
    });

    it("integer < integer", () => {
      assertBoxedFalse(testedFun(integer1, integer2));
    });

    it("pid < pid", () => {
      assertBoxedFalse(testedFun(pid1, pid2));
    });

    it("pid < tuple (always)", () => {
      assertBoxedFalse(testedFun(pid1, tuple3));
    });

    it("tuple < tuple", () => {
      assertBoxedFalse(testedFun(tuple2, tuple3));
    });

    it("atom > atom", () => {
      assertBoxedFalse(testedFun(atomB, atomA));
    });

    it("float > float", () => {
      assertBoxedFalse(testedFun(float2, float1));
    });

    it("float > integer", () => {
      assertBoxedFalse(testedFun(float2, integer1));
    });

    it("integer > float", () => {
      assertBoxedFalse(testedFun(integer2, float1));
    });

    it("integer > integer", () => {
      assertBoxedFalse(testedFun(integer2, integer1));
    });

    it("pid > pid", () => {
      assertBoxedFalse(testedFun(pid2, pid1));
    });

    it("tuple > tuple", () => {
      assertBoxedFalse(testedFun(tuple3, tuple2));
    });

    // TODO: reference, function, port, map, list, bitstring
  });

  describe("=</2", () => {
    const testedFun = Erlang["=</2"];

    it("atom == atom", () => {
      assertBoxedTrue(testedFun(atomA, atomA));
    });

    it("float == float", () => {
      assertBoxedTrue(testedFun(float1, float1));
    });

    it("float == integer", () => {
      assertBoxedTrue(testedFun(float1, integer1));
    });

    it("integer == float", () => {
      assertBoxedTrue(testedFun(integer1, float1));
    });

    it("integer == integer", () => {
      assertBoxedTrue(testedFun(integer1, integer1));
    });

    it("pid == pid", () => {
      assertBoxedTrue(testedFun(pid1, pid1));
    });

    it("tuple == tuple", () => {
      assertBoxedTrue(testedFun(tuple3, tuple3));
    });

    it("atom < atom", () => {
      assertBoxedTrue(testedFun(atomA, atomB));
    });

    it("float < atom (always)", () => {
      assertBoxedTrue(testedFun(float1, atomA));
    });

    it("float < float", () => {
      assertBoxedTrue(testedFun(float1, float2));
    });

    it("float < integer", () => {
      assertBoxedTrue(testedFun(float1, integer2));
    });

    it("integer < atom (always)", () => {
      assertBoxedTrue(testedFun(integer1, atomA));
    });

    it("integer < float", () => {
      assertBoxedTrue(testedFun(integer1, float2));
    });

    it("integer < integer", () => {
      assertBoxedTrue(testedFun(integer1, integer2));
    });

    it("pid < pid", () => {
      assertBoxedTrue(testedFun(pid1, pid2));
    });

    it("pid < tuple (always)", () => {
      assertBoxedTrue(testedFun(pid1, tuple3));
    });

    it("tuple < tuple", () => {
      assertBoxedTrue(testedFun(tuple2, tuple3));
    });

    it("atom > atom", () => {
      assertBoxedFalse(testedFun(atomB, atomA));
    });

    it("float > float", () => {
      assertBoxedFalse(testedFun(float2, float1));
    });

    it("float > integer", () => {
      assertBoxedFalse(testedFun(float2, integer1));
    });

    it("integer > float", () => {
      assertBoxedFalse(testedFun(integer2, float1));
    });

    it("integer > integer", () => {
      assertBoxedFalse(testedFun(integer2, integer1));
    });

    it("pid > pid", () => {
      assertBoxedFalse(testedFun(pid2, pid1));
    });

    it("tuple > tuple", () => {
      assertBoxedFalse(testedFun(tuple3, tuple2));
    });

    it("throws a not yet implemented error when the left argument type is not yet supported", () => {
      const expectedMessage =
        "Structural comparison currently supports only atoms, bitstrings, floats, integers, pids and tuples, got: [1, 2]";

      assert.throw(
        () => testedFun(list1, integer1),
        HologramInterpreterError,
        expectedMessage,
      );
    });

    it("throws a not yet implemented error when the right argument type is not yet supported", () => {
      const expectedMessage =
        "Structural comparison currently supports only atoms, bitstrings, floats, integers, pids and tuples, got: [1, 2]";

      assert.throw(
        () => testedFun(integer1, list1),
        HologramInterpreterError,
        expectedMessage,
      );
    });

    // TODO: reference, function, port, map, list, bitstring
  });

  describe("==/2", () => {
    const testedFun = Erlang["==/2"];

    it("atom == atom", () => {
      assertBoxedTrue(testedFun(atomA, atomA));
    });

    it("float == float", () => {
      assertBoxedTrue(testedFun(float1, float1));
    });

    it("float == integer", () => {
      assertBoxedTrue(testedFun(float1, integer1));
    });

    it("integer == float", () => {
      assertBoxedTrue(testedFun(integer1, float1));
    });

    it("integer == integer", () => {
      assertBoxedTrue(testedFun(integer1, integer1));
    });

    it("pid == pid", () => {
      assertBoxedTrue(testedFun(pid1, pid1));
    });

    it("tuple == tuple", () => {
      assertBoxedTrue(testedFun(tuple3, tuple3));
    });

    it("atom < atom", () => {
      assertBoxedFalse(testedFun(atomA, atomB));
    });

    it("float < atom (always)", () => {
      assertBoxedFalse(testedFun(float1, atomA));
    });

    it("float < float", () => {
      assertBoxedFalse(testedFun(float1, float2));
    });

    it("float < integer", () => {
      assertBoxedFalse(testedFun(float1, integer2));
    });

    it("integer < atom (always)", () => {
      assertBoxedFalse(testedFun(integer1, atomA));
    });

    it("integer < float", () => {
      assertBoxedFalse(testedFun(integer1, float2));
    });

    it("integer < integer", () => {
      assertBoxedFalse(testedFun(integer1, integer2));
    });

    it("pid < pid", () => {
      assertBoxedFalse(testedFun(pid1, pid2));
    });

    it("pid < tuple (always)", () => {
      assertBoxedFalse(testedFun(pid1, tuple3));
    });

    it("tuple < tuple", () => {
      assertBoxedFalse(testedFun(tuple2, tuple3));
    });

    it("atom > atom", () => {
      assertBoxedFalse(testedFun(atomB, atomA));
    });

    it("float > float", () => {
      assertBoxedFalse(testedFun(float2, float1));
    });

    it("float > integer", () => {
      assertBoxedFalse(testedFun(float2, integer1));
    });

    it("integer > float", () => {
      assertBoxedFalse(testedFun(integer2, float1));
    });

    it("integer > integer", () => {
      assertBoxedFalse(testedFun(integer2, integer1));
    });

    it("pid > pid", () => {
      assertBoxedFalse(testedFun(pid2, pid1));
    });

    it("tuple > tuple", () => {
      assertBoxedFalse(testedFun(tuple3, tuple2));
    });

    // TODO: reference, function, port, map, list, bitstring
  });

  describe(">/2", () => {
    const testedFun = Erlang[">/2"];

    it("atom == atom", () => {
      assertBoxedFalse(testedFun(atomA, atomA));
    });

    it("float == float", () => {
      assertBoxedFalse(testedFun(float1, float1));
    });

    it("float == integer", () => {
      assertBoxedFalse(testedFun(float1, integer1));
    });

    it("integer == float", () => {
      assertBoxedFalse(testedFun(integer1, float1));
    });

    it("integer == integer", () => {
      assertBoxedFalse(testedFun(integer1, integer1));
    });

    it("pid == pid", () => {
      assertBoxedFalse(testedFun(pid1, pid1));
    });

    it("tuple == tuple", () => {
      assertBoxedFalse(testedFun(tuple3, tuple3));
    });

    it("atom < atom", () => {
      assertBoxedFalse(testedFun(atomA, atomB));
    });

    it("float < atom (always)", () => {
      assertBoxedFalse(testedFun(float1, atomA));
    });

    it("float < float", () => {
      assertBoxedFalse(testedFun(float1, float2));
    });

    it("float < integer", () => {
      assertBoxedFalse(testedFun(float1, integer2));
    });

    it("integer < atom (always)", () => {
      assertBoxedFalse(testedFun(integer1, atomA));
    });

    it("integer < float", () => {
      assertBoxedFalse(testedFun(integer1, float2));
    });

    it("integer < integer", () => {
      assertBoxedFalse(testedFun(integer1, integer2));
    });

    it("pid < pid", () => {
      assertBoxedFalse(testedFun(pid1, pid2));
    });

    it("pid < tuple (always)", () => {
      assertBoxedFalse(testedFun(pid1, tuple3));
    });

    it("tuple < tuple", () => {
      assertBoxedFalse(testedFun(tuple2, tuple3));
    });

    it("atom > atom", () => {
      assertBoxedTrue(testedFun(atomB, atomA));
    });

    it("float > float", () => {
      assertBoxedTrue(testedFun(float2, float1));
    });

    it("float > integer", () => {
      assertBoxedTrue(testedFun(float2, integer1));
    });

    it("integer > float", () => {
      assertBoxedTrue(testedFun(integer2, float1));
    });

    it("integer > integer", () => {
      assertBoxedTrue(testedFun(integer2, integer1));
    });

    it("pid > pid", () => {
      assertBoxedTrue(testedFun(pid2, pid1));
    });

    it("tuple > tuple", () => {
      assertBoxedTrue(testedFun(tuple3, tuple2));
    });

    it("throws a not yet implemented error when the left argument type is not yet supported", () => {
      const expectedMessage =
        "Structural comparison currently supports only atoms, bitstrings, floats, integers, pids and tuples, got: [1, 2]";

      assert.throw(
        () => testedFun(list1, integer1),
        HologramInterpreterError,
        expectedMessage,
      );
    });

    it("throws a not yet implemented error when the right argument type is not yet supported", () => {
      const expectedMessage =
        "Structural comparison currently supports only atoms, bitstrings, floats, integers, pids and tuples, got: [1, 2]";

      assert.throw(
        () => testedFun(integer1, list1),
        HologramInterpreterError,
        expectedMessage,
      );
    });

    // TODO: reference, function, port, map, list, bitstring
  });

  describe(">=/2", () => {
    const testedFun = Erlang[">=/2"];

    it("atom == atom", () => {
      assertBoxedTrue(testedFun(atomA, atomA));
    });

    it("float == float", () => {
      assertBoxedTrue(testedFun(float1, float1));
    });

    it("float == integer", () => {
      assertBoxedTrue(testedFun(float1, integer1));
    });

    it("integer == float", () => {
      assertBoxedTrue(testedFun(integer1, float1));
    });

    it("integer == integer", () => {
      assertBoxedTrue(testedFun(integer1, integer1));
    });

    it("pid == pid", () => {
      assertBoxedTrue(testedFun(pid1, pid1));
    });

    it("tuple == tuple", () => {
      assertBoxedTrue(testedFun(tuple3, tuple3));
    });

    it("atom < atom", () => {
      assertBoxedFalse(testedFun(atomA, atomB));
    });

    it("float < atom (always)", () => {
      assertBoxedFalse(testedFun(float1, atomA));
    });

    it("float < float", () => {
      assertBoxedFalse(testedFun(float1, float2));
    });

    it("float < integer", () => {
      assertBoxedFalse(testedFun(float1, integer2));
    });

    it("integer < atom (always)", () => {
      assertBoxedFalse(testedFun(integer1, atomA));
    });

    it("integer < float", () => {
      assertBoxedFalse(testedFun(integer1, float2));
    });

    it("integer < integer", () => {
      assertBoxedFalse(testedFun(integer1, integer2));
    });

    it("pid < pid", () => {
      assertBoxedFalse(testedFun(pid1, pid2));
    });

    it("pid < tuple (always)", () => {
      assertBoxedFalse(testedFun(pid1, tuple3));
    });

    it("tuple < tuple", () => {
      assertBoxedFalse(testedFun(tuple2, tuple3));
    });

    it("atom > atom", () => {
      assertBoxedTrue(testedFun(atomB, atomA));
    });

    it("float > float", () => {
      assertBoxedTrue(testedFun(float2, float1));
    });

    it("float > integer", () => {
      assertBoxedTrue(testedFun(float2, integer1));
    });

    it("integer > float", () => {
      assertBoxedTrue(testedFun(integer2, float1));
    });

    it("integer > integer", () => {
      assertBoxedTrue(testedFun(integer2, integer1));
    });

    it("pid > pid", () => {
      assertBoxedTrue(testedFun(pid2, pid1));
    });

    it("tuple > tuple", () => {
      assertBoxedTrue(testedFun(tuple3, tuple2));
    });

    it("throws a not yet implemented error when the left argument type is not yet supported", () => {
      const expectedMessage =
        "Structural comparison currently supports only atoms, bitstrings, floats, integers, pids and tuples, got: [1, 2]";

      assert.throw(
        () => testedFun(list1, integer1),
        HologramInterpreterError,
        expectedMessage,
      );
    });

    it("throws a not yet implemented error when the right argument type is not yet supported", () => {
      const expectedMessage =
        "Structural comparison currently supports only atoms, bitstrings, floats, integers, pids and tuples, got: [1, 2]";

      assert.throw(
        () => testedFun(integer1, list1),
        HologramInterpreterError,
        expectedMessage,
      );
    });

    // TODO: reference, function, port, map, list, bitstring
  });

  describe("abs/1", () => {
    const testedFun = Erlang["abs/1"];

    it("positive float", () => {
      assert.deepStrictEqual(testedFun(Type.float(1.23)), Type.float(1.23));
    });

    it("negative float", () => {
      assert.deepStrictEqual(testedFun(Type.float(-1.23)), Type.float(1.23));
    });

    it("zero float", () => {
      assert.deepStrictEqual(testedFun(Type.float(0.0)), Type.float(0.0));
    });

    it("positive integer", () => {
      assert.deepStrictEqual(testedFun(Type.integer(123)), Type.integer(123));
    });

    it("negative integer", () => {
      assert.deepStrictEqual(testedFun(Type.integer(-123)), Type.integer(123));
    });

    it("zero integer", () => {
      assert.deepStrictEqual(testedFun(Type.integer(0)), Type.integer(0));
    });

    it("large positive integer", () => {
      assert.deepStrictEqual(
        testedFun(Type.integer(123456789012345678901234567890n)),
        Type.integer(123456789012345678901234567890n),
      );
    });

    it("large negative integer", () => {
      assert.deepStrictEqual(
        testedFun(Type.integer(-123456789012345678901234567890n)),
        Type.integer(123456789012345678901234567890n),
      );
    });

    it("raises ArgumentError if the argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    });
  });

  describe("andalso/2", () => {
    const andalso = Erlang["andalso/2"];

    it("returns false if the first argument is false", () => {
      const context = contextFixture({
        vars: {left: Type.boolean(false), right: Type.atom("abc")},
      });

      const result = andalso(
        (context) => context.vars.left,
        (context) => context.vars.right,
        context,
      );

      assertBoxedFalse(result);
    });

    it("returns the second argument if the first argument is true", () => {
      const context = contextFixture({
        vars: {left: Type.boolean(true), right: Type.atom("abc")},
      });

      const result = andalso(
        (context) => context.vars.left,
        (context) => context.vars.right,
        context,
      );

      assert.deepStrictEqual(result, Type.atom("abc"));
    });

    it("doesn't evaluate the second argument if the first argument is false", () => {
      const result = andalso(
        (_context) => Type.boolean(false),
        (_context) => {
          throw new Error("impossible");
        },
        contextFixture(),
      );

      assertBoxedFalse(result);
    });

    it("raises ArgumentError if the first argument is not a boolean", () => {
      const context = contextFixture({
        vars: {left: Type.nil(), right: Type.boolean(true)},
      });

      assertBoxedError(
        () =>
          andalso(
            (context) => context.vars.left,
            (context) => context.vars.right,
            context,
          ),
        "ArgumentError",
        "argument error: nil",
      );
    });
  });

  describe("append_element/2", () => {
    const testedFun = Erlang["append_element/2"];

    it("appends element to tuple", () => {
      const tuple = Type.tuple([Type.integer(1), Type.integer(2)]);
      const result = testedFun(tuple, Type.integer(3));

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.integer(1), Type.integer(2), Type.integer(3)]),
      );
    });

    it("appends to empty tuple", () => {
      const tuple = Type.tuple([]);
      const result = testedFun(tuple, Type.atom("a"));

      assert.deepStrictEqual(result, Type.tuple([Type.atom("a")]));
    });

    it("appends different types", () => {
      const tuple = Type.tuple([Type.integer(1)]);
      const result = testedFun(tuple, Type.atom("abc"));

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.integer(1), Type.atom("abc")]),
      );
    });

    it("raises ArgumentError if first argument is not a tuple", () => {
      assertBoxedError(
        () => testedFun(Type.list([integer1]), Type.integer(2)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a tuple"),
      );
    });
  });

  describe("apply/2", () => {
    const testedFun = Erlang["apply/2"];

    it("applies anonymous function with arguments", () => {
      const fun = Type.anonymousFunction(
        2,
        [
          {
            params: (ctx) => [Type.variablePattern("a"), Type.variablePattern("b")],
            guards: [],
            body: (ctx) => {
              const a = ctx.vars.a;
              const b = ctx.vars.b;
              return Type.integer(a.value + b.value);
            },
          },
        ],
        Interpreter.buildContext({ module: Type.atom("Elixir.Test"), vars: {} }),
      );
      const args = Type.list([Type.integer(3), Type.integer(4)]);
      const result = testedFun(fun, args);
      assert.deepStrictEqual(result, Type.integer(7));
    });

    it("raises ArgumentError if first argument is not a function", () => {
      assertBoxedError(
        () => testedFun(Type.atom("not_fun"), Type.list([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a function"),
      );
    });

    it("raises ArgumentError if second argument is not a list", () => {
      const fun = Type.anonymousFunction(0, [], Interpreter.buildContext({ module: Type.atom("Elixir.Test"), vars: {} }));
      assertBoxedError(
        () => testedFun(fun, Type.atom("not_list")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    });

    it("raises ArgumentError if second argument is not a proper list", () => {
      const fun = Type.anonymousFunction(0, [], Interpreter.buildContext({ module: Type.atom("Elixir.Test"), vars: {} }));
      assertBoxedError(
        () => testedFun(fun, Type.improperList([Type.integer(1), Type.integer(2)])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a proper list"),
      );
    });
  });

  describe("apply/3", () => {
    const testedFun = Erlang["apply/3"];

    it("applies module function with arguments", () => {
      const result = testedFun(
        Type.atom("erlang"),
        Type.atom("+"),
        Type.list([Type.integer(2), Type.integer(3)]),
      );
      assert.deepStrictEqual(result, Type.integer(5));
    });

    it("raises ArgumentError if first argument is not an atom", () => {
      assertBoxedError(
        () => testedFun(Type.integer(1), Type.atom("func"), Type.list([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    });

    it("raises ArgumentError if second argument is not an atom", () => {
      assertBoxedError(
        () => testedFun(Type.atom("erlang"), Type.integer(1), Type.list([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    });

    it("raises ArgumentError if third argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("erlang"), Type.atom("abs"), Type.atom("not_list")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    });
  });

  describe("atom_to_binary/1", () => {
    it("delegates to atom_to_binary/2", () => {
      const atom = Type.atom("全息图");
      const result = Erlang["atom_to_binary/1"](atom);
      const expected = Erlang["atom_to_binary/2"](atom, Type.atom("utf8"));

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("atom_to_binary/2", () => {
    const atom = Type.atom("全息图");
    const encoding = Type.atom("utf8");
    const testedFun = Erlang["atom_to_binary/2"];

    it("utf8 encoding", () => {
      const result = testedFun(atom, encoding);

      assert.deepStrictEqual(result, Type.bitstring("全息图"));
    });

    it("raises ArgumentError if the first arg is not an atom", () => {
      assertBoxedError(
        () => testedFun(Type.integer(123), encoding),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    });

    // TODO: remove this test when other encodings are implemented
    it("raises ArgumentError if the second arg is not equal to :utf8", () => {
      assert.throw(
        () => testedFun(atom, Type.atom("latin1")),
        HologramInterpreterError,
        "encodings other than utf8 are not yet implemented in Hologram",
      );
    });
  });

  describe("atom_to_list/1", () => {
    const atom_to_list = Erlang["atom_to_list/1"];

    it("empty atom", () => {
      const result = atom_to_list(Type.atom(""));
      assert.deepStrictEqual(result, Type.list());
    });

    it("ASCII atom", () => {
      const result = atom_to_list(Type.atom("abc"));

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(97), Type.integer(98), Type.integer(99)]),
      );
    });

    it("Unicode atom", () => {
      const result = atom_to_list(Type.atom("全息图"));

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.integer(20840),
          Type.integer(24687),
          Type.integer(22270),
        ]),
      );
    });

    it("not an atom", () => {
      assertBoxedError(
        () => atom_to_list(Type.integer(123)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    });
  });

  describe("binary_to_atom/1", () => {
    it("delegates to binary_to_atom/2", () => {
      const binary = Type.bitstring("全息图");
      const result = Erlang["binary_to_atom/1"](binary);
      const expected = Erlang["binary_to_atom/2"](binary, Type.atom("utf8"));

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("binary_to_atom/2", () => {
    const binary_to_atom = Erlang["binary_to_atom/2"];
    const encoding = Type.atom("utf8");

    it("converts a binary bitstring to an already existing atom", () => {
      const binary = Type.bitstring("Elixir.Kernel");
      const result = binary_to_atom(binary, encoding);

      assert.deepStrictEqual(result, Type.alias("Kernel"));
    });

    it("converts a binary bitstring to a not existing yet atom", () => {
      const randomStr = `${Math.random()}`;
      const binary = Type.bitstring(randomStr);
      const result = binary_to_atom(binary, encoding);

      assert.deepStrictEqual(result, Type.atom(randomStr));
    });

    it("raises ArgumentError if the first argument is a non-binary bitstring", () => {
      assertBoxedError(
        () => binary_to_atom(Type.bitstring([1, 0, 1]), encoding),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("raises ArgumentErorr if the first argument is not a bitstring", () => {
      assertBoxedError(
        () => binary_to_atom(Type.atom("abc"), encoding),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });
  });

  describe("binary_to_existing_atom/1", () => {
    it("delegates to binary_to_atom/1", () => {
      const randomStr = `${Math.random()}`;
      const binary = Type.bitstring(randomStr);

      const result = Erlang["binary_to_existing_atom/1"](binary);
      const expected = Erlang["binary_to_atom/1"](binary);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("binary_to_existing_atom/2", () => {
    it("delegates to binary_to_atom/2", () => {
      const randomStr = `${Math.random()}`;
      const binary = Type.bitstring(randomStr);
      const encoding = Type.atom("utf8");

      const result = Erlang["binary_to_existing_atom/2"](binary, encoding);
      const expected = Erlang["binary_to_atom/2"](binary, encoding);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("binary_to_integer/1", () => {
    const binary_to_integer = Erlang["binary_to_integer/1"];

    it("delegates to binary_to_integer/2 with base 10", () => {
      const binary = Type.bitstring("123");
      const result = binary_to_integer(binary);
      const expected = Erlang["binary_to_integer/2"](binary, Type.integer(10));

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("binary_to_integer/2", () => {
    const binary_to_integer = Erlang["binary_to_integer/2"];

    describe("different bases", () => {
      it("base 2", () => {
        const binary = Type.bitstring("1111");
        const base = Type.integer(2);
        const result = binary_to_integer(binary, base);
        const expected = Type.integer(15);

        assert.deepStrictEqual(result, expected);
      });

      it("base 8", () => {
        const binary = Type.bitstring("177");
        const base = Type.integer(8);
        const result = binary_to_integer(binary, base);
        const expected = Type.integer(127);

        assert.deepStrictEqual(result, expected);
      });

      it("base 10", () => {
        const binary = Type.bitstring("123");
        const base = Type.integer(10);
        const result = binary_to_integer(binary, base);
        const expected = Type.integer(123);

        assert.deepStrictEqual(result, expected);
      });

      it("base 16", () => {
        const binary = Type.bitstring("3FF");
        const base = Type.integer(16);
        const result = binary_to_integer(binary, base);
        const expected = Type.integer(1023);

        assert.deepStrictEqual(result, expected);
      });

      it("base 36", () => {
        const binary = Type.bitstring("ZZ");
        const base = Type.integer(36);
        const result = binary_to_integer(binary, base);
        const expected = Type.integer(1295);

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("sign handling", () => {
      it("positive integer without sign", () => {
        const binary = Type.bitstring("123");
        const base = Type.integer(10);
        const result = binary_to_integer(binary, base);
        const expected = Type.integer(123);

        assert.deepStrictEqual(result, expected);
      });

      it("positive integer with plus sign", () => {
        const binary = Type.bitstring("+123");
        const base = Type.integer(10);
        const result = binary_to_integer(binary, base);
        const expected = Type.integer(123);

        assert.deepStrictEqual(result, expected);
      });

      it("negative integer", () => {
        const binary = Type.bitstring("-123");
        const base = Type.integer(10);
        const result = binary_to_integer(binary, base);
        const expected = Type.integer(-123);

        assert.deepStrictEqual(result, expected);
      });

      it("zero", () => {
        const binary = Type.bitstring("0");
        const base = Type.integer(10);
        const result = binary_to_integer(binary, base);
        const expected = Type.integer(0);

        assert.deepStrictEqual(result, expected);
      });

      it("positive zero", () => {
        const binary = Type.bitstring("+0");
        const base = Type.integer(10);
        const result = binary_to_integer(binary, base);
        const expected = Type.integer(0);

        assert.deepStrictEqual(result, expected);
      });

      it("negative zero", () => {
        const binary = Type.bitstring("-0");
        const base = Type.integer(10);
        const result = binary_to_integer(binary, base);
        const expected = Type.integer(0);

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("case sensitivity", () => {
      it("lowercase letters", () => {
        const binary = Type.bitstring("abcd");
        const base = Type.integer(16);
        const result = binary_to_integer(binary, base);
        const expected = Type.integer(43981);

        assert.deepStrictEqual(result, expected);
      });

      it("uppercase letters", () => {
        const binary = Type.bitstring("ABCD");
        const base = Type.integer(16);
        const result = binary_to_integer(binary, base);
        const expected = Type.integer(43981);

        assert.deepStrictEqual(result, expected);
      });

      it("mixed case letters", () => {
        const binary = Type.bitstring("aBcD");
        const base = Type.integer(16);
        const result = binary_to_integer(binary, base);
        const expected = Type.integer(43981);

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("error cases", () => {
      it("raises ArgumentError if the first argument is not a binary", () => {
        assertBoxedError(
          () => binary_to_integer(Type.atom("abc"), Type.integer(10)),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a binary"),
        );
      });

      it("raises ArgumentError if the first argument is a non-binary bitstring", () => {
        assertBoxedError(
          () => binary_to_integer(Type.bitstring([1, 0, 1]), Type.integer(10)),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a binary"),
        );
      });

      it("raises ArgumentError if binary is empty", () => {
        assertBoxedError(
          () => binary_to_integer(Type.bitstring(""), Type.integer(10)),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(
            1,
            "not a textual representation of an integer",
          ),
        );
      });

      it("raises ArgumentError if binary contains characters outside of the alphabet", () => {
        assertBoxedError(
          () => binary_to_integer(Type.bitstring("123"), Type.integer(2)),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(
            1,
            "not a textual representation of an integer",
          ),
        );
      });

      it("raises ArgumentError if the second argument is not an integer", () => {
        assertBoxedError(
          () => binary_to_integer(Type.bitstring("123"), Type.atom("abc")),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(
            2,
            "not an integer in the range 2 through 36",
          ),
        );
      });

      it("raises ArgumentError if base is less than 2", () => {
        assertBoxedError(
          () => binary_to_integer(Type.bitstring("123"), Type.integer(1)),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(
            2,
            "not an integer in the range 2 through 36",
          ),
        );
      });

      it("raises ArgumentError if base is greater than 36", () => {
        assertBoxedError(
          () => binary_to_integer(Type.bitstring("123"), Type.integer(37)),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(
            2,
            "not an integer in the range 2 through 36",
          ),
        );
      });
    });
  });

  describe("binary_to_float/1", () => {
    const testedFun = Erlang["binary_to_float/1"];

    it("converts binary with positive float", () => {
      const result = testedFun(Type.bitstring("3.14"));

      assert.deepStrictEqual(result, Type.float(3.14));
    });

    it("converts binary with negative float", () => {
      const result = testedFun(Type.bitstring("-2.5"));

      assert.deepStrictEqual(result, Type.float(-2.5));
    });

    it("converts binary with scientific notation (lowercase e)", () => {
      const result = testedFun(Type.bitstring("1.5e2"));

      assert.deepStrictEqual(result, Type.float(150.0));
    });

    it("converts binary with scientific notation (uppercase E)", () => {
      const result = testedFun(Type.bitstring("1.5E2"));

      assert.deepStrictEqual(result, Type.float(150.0));
    });

    it("converts binary with negative exponent", () => {
      const result = testedFun(Type.bitstring("1.5e-2"));

      assert.deepStrictEqual(result, Type.float(0.015));
    });

    it("converts integer with exponent (no decimal point)", () => {
      const result = testedFun(Type.bitstring("15e1"));

      assert.deepStrictEqual(result, Type.float(150.0));
    });

    it("raises ArgumentError if argument is not a binary", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("raises ArgumentError if binary doesn't represent a float (integer without exponent)", () => {
      assertBoxedError(
        () => testedFun(Type.bitstring("42")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a textual representation of a float"),
      );
    });

    it("raises ArgumentError if binary is not a valid number", () => {
      assertBoxedError(
        () => testedFun(Type.bitstring("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a textual representation of a float"),
      );
    });
  });

  describe("binary_to_list/1", () => {
    const testedFun = Erlang["binary_to_list/1"];

    it("converts empty binary to empty list", () => {
      const result = testedFun(Type.bitstring(""));

      assert.deepStrictEqual(result, Type.list());
    });

    it("converts binary to list of byte values", () => {
      const result = testedFun(Type.bitstring("ABC"));

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(65), Type.integer(66), Type.integer(67)]),
      );
    });

    it("converts binary with UTF-8 characters", () => {
      const result = testedFun(Type.bitstring("Hi"));

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(72), Type.integer(105)]),
      );
    });

    it("raises ArgumentError if argument is not a binary", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });
  });

  describe("bit_size/1", () => {
    const bit_size = Erlang["bit_size/1"];

    it("bitstring", () => {
      const myBitstring = Type.bitstring([
        Type.bitstringSegment(Type.integer(2), {
          type: "integer",
          size: Type.integer(7),
        }),
      ]);

      const result = bit_size(myBitstring);

      assert.deepStrictEqual(result, Type.integer(7));
    });

    it("not bitstring", () => {
      const myAtom = Type.atom("abc");

      assertBoxedError(
        () => bit_size(myAtom),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a bitstring"),
      );
    });
  });

  describe("byte_size/1", () => {
    const byte_size = Erlang["byte_size/1"];

    it("empty bitstring", () => {
      const bitstring = Type.bitstring("");
      const result = byte_size(bitstring);

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("binary bitstring", () => {
      const bitstring = Type.bitstring("abc");
      const result = byte_size(bitstring);

      assert.deepStrictEqual(result, Type.integer(3));
    });

    it("non-binary bitstring", () => {
      const bitstring = Type.bitstring([1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]);
      const result = byte_size(bitstring);

      assert.deepStrictEqual(result, Type.integer(2));
    });

    it("not bitstring", () => {
      const atom = Type.atom("abc");

      assertBoxedError(
        () => byte_size(atom),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a bitstring"),
      );
    });
  });

  describe("ceil/1", () => {
    const testedFun = Erlang["ceil/1"];

    it("returns the integer unchanged", () => {
      const result = testedFun(Type.integer(42));

      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("returns ceiling of positive float", () => {
      const result = testedFun(Type.float(2.3));

      assert.deepStrictEqual(result, Type.integer(3));
    });

    it("returns ceiling of negative float", () => {
      const result = testedFun(Type.float(-2.3));

      assert.deepStrictEqual(result, Type.integer(-2));
    });

    it("returns 1 for 0.5", () => {
      const result = testedFun(Type.float(0.5));

      assert.deepStrictEqual(result, Type.integer(1));
    });

    it("returns 0 for -0.5", () => {
      const result = testedFun(Type.float(-0.5));

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("returns 0 for 0.0", () => {
      const result = testedFun(Type.float(0.0));

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("returns 0 for -0.0", () => {
      const result = testedFun(Type.float(-0.0));

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("raises ArgumentError if argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    });
  });

  describe("div/2", () => {
    const testedFun = Erlang["div/2"];

    it("divides positive integers", () => {
      const result = testedFun(Type.integer(10), Type.integer(3));

      assert.deepStrictEqual(result, Type.integer(3));
    });

    it("divides negative dividend by positive divisor", () => {
      const result = testedFun(Type.integer(-10), Type.integer(3));

      assert.deepStrictEqual(result, Type.integer(-3));
    });

    it("divides positive dividend by negative divisor", () => {
      const result = testedFun(Type.integer(10), Type.integer(-3));

      assert.deepStrictEqual(result, Type.integer(-3));
    });

    it("divides negative integers", () => {
      const result = testedFun(Type.integer(-10), Type.integer(-3));

      assert.deepStrictEqual(result, Type.integer(3));
    });

    it("divides evenly", () => {
      const result = testedFun(Type.integer(12), Type.integer(4));

      assert.deepStrictEqual(result, Type.integer(3));
    });

    it("truncates toward zero for positive result", () => {
      const result = testedFun(Type.integer(7), Type.integer(2));

      assert.deepStrictEqual(result, Type.integer(3));
    });

    it("truncates toward zero for negative result", () => {
      const result = testedFun(Type.integer(-7), Type.integer(2));

      assert.deepStrictEqual(result, Type.integer(-3));
    });

    it("divides by 1", () => {
      const result = testedFun(Type.integer(42), Type.integer(1));

      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("divides by -1", () => {
      const result = testedFun(Type.integer(42), Type.integer(-1));

      assert.deepStrictEqual(result, Type.integer(-42));
    });

    it("divides 0 by non-zero", () => {
      const result = testedFun(Type.integer(0), Type.integer(5));

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("raises ArithmeticError when dividing by zero", () => {
      assertBoxedError(
        () => testedFun(Type.integer(5), Type.integer(0)),
        "ArithmeticError",
        "bad argument in arithmetic expression: div(5, 0)",
      );
    });

    it("raises ArgumentError if the first argument is a float", () => {
      assertBoxedError(
        () => testedFun(Type.float(5.5), Type.integer(2)),
        "ArgumentError",
        "bad argument in arithmetic expression: div(5.5, 2)",
      );
    });

    it("raises ArgumentError if the second argument is a float", () => {
      assertBoxedError(
        () => testedFun(Type.integer(5), Type.float(2.5)),
        "ArgumentError",
        "bad argument in arithmetic expression: div(5, 2.5)",
      );
    });

    it("raises ArgumentError if the first argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.integer(2)),
        "ArgumentError",
        "bad argument in arithmetic expression: div(:abc, 2)",
      );
    });

    it("raises ArgumentError if the second argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.integer(5), Type.atom("abc")),
        "ArgumentError",
        "bad argument in arithmetic expression: div(5, :abc)",
      );
    });
  });

  describe("delete_element/2", () => {
    const testedFun = Erlang["delete_element/2"];

    it("deletes element from beginning of tuple", () => {
      const tuple = Type.tuple([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);
      const result = testedFun(Type.integer(1), tuple);

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.integer(2), Type.integer(3)]),
      );
    });

    it("deletes element from middle of tuple", () => {
      const tuple = Type.tuple([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);
      const result = testedFun(Type.integer(2), tuple);

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.integer(1), Type.integer(3)]),
      );
    });

    it("deletes element from end of tuple", () => {
      const tuple = Type.tuple([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);
      const result = testedFun(Type.integer(3), tuple);

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.integer(1), Type.integer(2)]),
      );
    });

    it("deletes only element from tuple", () => {
      const tuple = Type.tuple([Type.atom("a")]);
      const result = testedFun(Type.integer(1), tuple);

      assert.deepStrictEqual(result, Type.tuple([]));
    });

    it("raises ArgumentError if first argument is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), tuple2),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    });

    it("raises ArgumentError if second argument is not a tuple", () => {
      assertBoxedError(
        () => testedFun(Type.integer(1), Type.list([integer1])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a tuple"),
      );
    });

    it("raises ArgumentError if index is less than 1", () => {
      assertBoxedError(
        () => testedFun(Type.integer(0), tuple2),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    });

    it("raises ArgumentError if index is greater than tuple size", () => {
      assertBoxedError(
        () => testedFun(Type.integer(3), tuple2),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    });
  });

  describe("date/0", () => {
    const testedFun = Erlang["date/0"];

    it("returns current date as {Year, Month, Day} tuple", () => {
      const result = testedFun();
      const now = new Date();

      assert.ok(Type.isTuple(result));
      assert.strictEqual(result.data.length, 3);
      assert.deepStrictEqual(result.data[0], Type.integer(BigInt(now.getFullYear())));
      assert.deepStrictEqual(result.data[1], Type.integer(BigInt(now.getMonth() + 1)));
      assert.deepStrictEqual(result.data[2], Type.integer(BigInt(now.getDate())));
    });
  });

  describe("element/2", () => {
    const element = Erlang["element/2"];

    const tuple = Type.tuple([
      Type.integer(5),
      Type.integer(6),
      Type.integer(7),
    ]);

    it("returns the element at the one-based index in the tuple", () => {
      const result = element(Type.integer(2), tuple);
      assert.deepStrictEqual(result, Type.integer(6));
    });

    it("raises ArgumentError if the first argument is not an integer", () => {
      assertBoxedError(
        () => element(Type.atom("abc"), tuple),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    });

    it("raises ArgumentError if the second argument is not a tuple", () => {
      assertBoxedError(
        () => element(Type.integer(1), Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a tuple"),
      );
    });

    it("raises ArgumentError if the given index is greater than the number of elements in the tuple", () => {
      assertBoxedError(
        () => element(Type.integer(10), tuple),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    });

    it("raises ArgumentError if the given index is smaller than 1", () => {
      assertBoxedError(
        () => element(Type.integer(0), tuple),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    });
  });

  it("error/1", () => {
    const error = Erlang["error/1"];
    const reason = Type.errorStruct("MyError", "my message");

    assertBoxedError(() => error(reason), "MyError", "my message");
  });

  it("error/2", () => {
    const error = Erlang["error/2"];
    const reason = Type.errorStruct("MyError", "my message");
    const args = Type.list([Type.integer(1, Type.integer(2))]);

    assertBoxedError(() => error(reason, args), "MyError", "my message");
  });

  describe("float_to_binary/2", () => {
    const float_to_binary = Erlang["float_to_binary/2"];

    const float = Type.float(0.1 + 0.2);
    const integer = Type.integer(123);
    const opts = Type.list([Type.atom("short")]);

    it(":short option", () => {
      const result = float_to_binary(float, opts);
      const expected = Type.bitstring("0.30000000000000004");

      assert.deepStrictEqual(result, expected);
    });

    it("raises ArgumentError if the first argument is not a float", () => {
      assertBoxedError(
        () => float_to_binary(integer, opts),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a float"),
      );
    });

    it("raises ArgumentError if the second argument is not a list", () => {
      const opts = Type.tuple([Type.atom("short")]);

      assertBoxedError(
        () => float_to_binary(float, opts),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    });

    it("raises ArgumentError if the second argument is not a proper list", () => {
      const opts = Type.improperList([
        Type.tuple([Type.atom("decimals"), Type.integer(4)]),
        Type.atom("compact"),
      ]);

      assertBoxedError(
        () => float_to_binary(float, opts),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a proper list"),
      );
    });

    // TODO: remove when other options are supported
    it("raises HologramInterpreterError if there are 0 options specified", () => {
      const opts = Type.list();

      assert.throw(
        () => float_to_binary(float, opts),
        HologramInterpreterError,
        ":erlang.float_to_binary/2 options other than :short are not yet implemented in Hologram",
      );
    });

    // TODO: remove when other options are supported
    it("raises HologramInterpreterError if there are 2+ options specified", () => {
      const opts = Type.list([
        Type.tuple([Type.atom("decimals"), Type.integer(4)]),
        Type.atom("compact"),
      ]);

      assert.throw(
        () => float_to_binary(float, opts),
        HologramInterpreterError,
        ":erlang.float_to_binary/2 options other than :short are not yet implemented in Hologram",
      );
    });

    // TODO: remove when other options are supported
    it("raises HologramInterpreterError if not yet implemented option is specified", () => {
      const opts = Type.list([Type.atom("compact")]);

      assert.throw(
        () => float_to_binary(float, opts),
        HologramInterpreterError,
        ":erlang.float_to_binary/2 options other than :short are not yet implemented in Hologram",
      );
    });
  });

  describe("floor/1", () => {
    const testedFun = Erlang["floor/1"];

    it("returns the integer unchanged", () => {
      const result = testedFun(Type.integer(42));

      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("returns floor of positive float", () => {
      const result = testedFun(Type.float(2.7));

      assert.deepStrictEqual(result, Type.integer(2));
    });

    it("returns floor of negative float", () => {
      const result = testedFun(Type.float(-2.3));

      assert.deepStrictEqual(result, Type.integer(-3));
    });

    it("returns 0 for 0.5", () => {
      const result = testedFun(Type.float(0.5));

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("returns -1 for -0.5", () => {
      const result = testedFun(Type.float(-0.5));

      assert.deepStrictEqual(result, Type.integer(-1));
    });

    it("returns 0 for 0.0", () => {
      const result = testedFun(Type.float(0.0));

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("returns 0 for -0.0", () => {
      const result = testedFun(Type.float(-0.0));

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("raises ArgumentError if argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    });
  });

  describe("float/1", () => {
    const testedFun = Erlang["float/1"];

    it("returns the float unchanged", () => {
      const result = testedFun(Type.float(3.14));

      assert.deepStrictEqual(result, Type.float(3.14));
    });

    it("converts positive integer to float", () => {
      const result = testedFun(Type.integer(42));

      assert.deepStrictEqual(result, Type.float(42.0));
    });

    it("converts negative integer to float", () => {
      const result = testedFun(Type.integer(-42));

      assert.deepStrictEqual(result, Type.float(-42.0));
    });

    it("converts 0 to 0.0", () => {
      const result = testedFun(Type.integer(0));

      assert.deepStrictEqual(result, Type.float(0.0));
    });

    it("raises ArgumentError if argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    });
  });

  describe("hd/1", () => {
    const hd = Erlang["hd/1"];

    it("returns the first item in the list", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const result = hd(list);

      assert.deepStrictEqual(result, Type.integer(1));
    });

    it("raises ArgumentError if the argument is an empty list", () => {
      assertBoxedError(
        () => hd(Type.list()),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a nonempty list"),
      );
    });

    it("raises ArgumentError if the argument is not a list", () => {
      assertBoxedError(
        () => hd(Type.integer(123)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a nonempty list"),
      );
    });
  });

  describe("integer_to_binary/1", () => {
    it("delegates to integer_to_binary/2", () => {
      const integer = Type.integer(123123);
      const result = Erlang["integer_to_binary/1"](integer);
      const expected = Erlang["integer_to_binary/2"](integer, Type.integer(10));

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("integer_to_binary/2", () => {
    const integer_to_binary = Erlang["integer_to_binary/2"];

    describe("positive integer", () => {
      it("base = 1", () => {
        assertBoxedError(
          () => integer_to_binary(Type.integer(123123), Type.integer(1)),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(
            2,
            "not an integer in the range 2 through 36",
          ),
        );
      });

      it("base = 2", () => {
        const result = integer_to_binary(Type.integer(123123), Type.integer(2));

        const expected = Type.bitstring("11110000011110011");

        assert.deepStrictEqual(result, expected);
      });

      it("base = 16", () => {
        const result = integer_to_binary(
          Type.integer(123123),
          Type.integer(16),
        );

        const expected = Type.bitstring("1E0F3");

        assert.deepStrictEqual(result, expected);
      });

      it("base = 36", () => {
        const result = integer_to_binary(
          Type.integer(123123),
          Type.integer(36),
        );

        const expected = Type.bitstring("2N03");

        assert.deepStrictEqual(result, expected);
      });

      it("base = 37", () => {
        assertBoxedError(
          () => integer_to_binary(Type.integer(123123), Type.integer(37)),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(
            2,
            "not an integer in the range 2 through 36",
          ),
        );
      });
    });

    it("negative integer", () => {
      const result = integer_to_binary(Type.integer(-123123), Type.integer(16));

      const expected = Type.bitstring("-1E0F3");

      assert.deepStrictEqual(result, expected);
    });

    it("1st argument (integer) is not an integer", () => {
      assertBoxedError(
        () => integer_to_binary(Type.atom("abc"), Type.integer(16)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    });

    it("2nd argument (base) is not an integer", () => {
      assertBoxedError(
        () => integer_to_binary(Type.integer(123123), Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          2,
          "not an integer in the range 2 through 36",
        ),
      );
    });
  });

  describe("integer_to_list/1", () => {
    const testedFun = Erlang["integer_to_list/1"];

    it("converts positive integer to list", () => {
      const result = testedFun(Type.integer(123));

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(49), Type.integer(50), Type.integer(51)]),
      );
    });

    it("converts negative integer to list", () => {
      const result = testedFun(Type.integer(-456));

      assert.deepStrictEqual(
        result,
        Type.list([
          Type.integer(45),
          Type.integer(52),
          Type.integer(53),
          Type.integer(54),
        ]),
      );
    });

    it("converts zero to list", () => {
      const result = testedFun(Type.integer(0));

      assert.deepStrictEqual(result, Type.list([Type.integer(48)]));
    });

    it("raises ArgumentError if argument is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    });
  });

  describe("integer_to_list/2", () => {
    const testedFun = Erlang["integer_to_list/2"];

    it("converts integer to list in base 10", () => {
      const result = testedFun(Type.integer(123), Type.integer(10));

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(49), Type.integer(50), Type.integer(51)]),
      );
    });

    it("converts integer to list in base 2", () => {
      const result = testedFun(Type.integer(5), Type.integer(2));

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(49), Type.integer(48), Type.integer(49)]),
      );
    });

    it("converts integer to list in base 16", () => {
      const result = testedFun(Type.integer(255), Type.integer(16));

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(102), Type.integer(102)]),
      );
    });

    it("converts integer to list in base 36", () => {
      const result = testedFun(Type.integer(35), Type.integer(36));

      assert.deepStrictEqual(result, Type.list([Type.integer(122)]));
    });

    it("raises ArgumentError if first argument is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.integer(10)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    });

    it("raises ArgumentError if second argument is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.integer(123), Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });

    it("raises ArgumentError if base is less than 2", () => {
      assertBoxedError(
        () => testedFun(Type.integer(123), Type.integer(1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          2,
          "not an integer in the range 2 through 36",
        ),
      );
    });

    it("raises ArgumentError if base is greater than 36", () => {
      assertBoxedError(
        () => testedFun(Type.integer(123), Type.integer(37)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          2,
          "not an integer in the range 2 through 36",
        ),
      );
    });
  });

  describe("insert_element/3", () => {
    const testedFun = Erlang["insert_element/3"];

    it("inserts element at beginning of tuple", () => {
      const tuple = Type.tuple([Type.integer(2), Type.integer(3)]);
      const result = testedFun(Type.integer(1), tuple, Type.integer(1));

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.integer(1), Type.integer(2), Type.integer(3)]),
      );
    });

    it("inserts element in middle of tuple", () => {
      const tuple = Type.tuple([Type.integer(1), Type.integer(3)]);
      const result = testedFun(Type.integer(2), tuple, Type.integer(2));

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.integer(1), Type.integer(2), Type.integer(3)]),
      );
    });

    it("inserts element at end of tuple", () => {
      const tuple = Type.tuple([Type.integer(1), Type.integer(2)]);
      const result = testedFun(Type.integer(3), tuple, Type.integer(3));

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.integer(1), Type.integer(2), Type.integer(3)]),
      );
    });

    it("inserts into empty tuple", () => {
      const tuple = Type.tuple([]);
      const result = testedFun(Type.integer(1), tuple, Type.atom("a"));

      assert.deepStrictEqual(result, Type.tuple([Type.atom("a")]));
    });

    it("inserts different types", () => {
      const tuple = Type.tuple([Type.integer(1)]);
      const result = testedFun(Type.integer(1), tuple, Type.atom("abc"));

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.atom("abc"), Type.integer(1)]),
      );
    });

    it("raises ArgumentError if first argument is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), tuple2, Type.integer(1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    });

    it("raises ArgumentError if second argument is not a tuple", () => {
      assertBoxedError(
        () =>
          testedFun(Type.integer(1), Type.list([integer1]), Type.integer(2)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a tuple"),
      );
    });

    it("raises ArgumentError if index is less than 1", () => {
      assertBoxedError(
        () => testedFun(Type.integer(0), tuple2, Type.integer(1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    });

    it("raises ArgumentError if index is greater than tuple size + 1", () => {
      assertBoxedError(
        () => testedFun(Type.integer(4), tuple2, Type.integer(1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    });
  });

  describe("is_atom/1", () => {
    const is_atom = Erlang["is_atom/1"];

    it("atom", () => {
      assertBoxedTrue(is_atom(Type.atom("abc")));
    });

    it("non-atom", () => {
      assertBoxedFalse(is_atom(Type.integer(123)));
    });
  });

  describe("is_binary/1", () => {
    const is_binary = Erlang["is_binary/1"];

    it("binary bitsting", () => {
      assertBoxedTrue(is_binary(Type.bitstring("abc")));
    });

    it("non-binary bitstring", () => {
      assertBoxedFalse(is_binary(Type.bitstring([0, 1, 0])));
    });

    it("non-bitstring", () => {
      assertBoxedFalse(is_binary(Type.atom("abc")));
    });
  });

  describe("is_bitstring/1", () => {
    const is_bitstring = Erlang["is_bitstring/1"];

    it("bitstring", () => {
      assertBoxedTrue(is_bitstring(Type.bitstring([0, 1, 0])));
    });

    it("non-bitstring", () => {
      assertBoxedFalse(is_bitstring(Type.atom("abc")));
    });
  });

  describe("is_boolean/1", () => {
    const testedFun = Erlang["is_boolean/1"];

    it("boolean", () => {
      assertBoxedTrue(testedFun(Type.boolean(true)));
    });

    it("non-boolean", () => {
      assertBoxedFalse(testedFun(Type.nil()));
    });
  });

  describe("is_float/1", () => {
    const is_float = Erlang["is_float/1"];

    it("float", () => {
      assertBoxedTrue(is_float(Type.float(1.0)));
    });

    it("non-float", () => {
      assertBoxedFalse(is_float(Type.atom("abc")));
    });
  });

  describe("is_function/1", () => {
    const is_function = Erlang["is_function/1"];

    it("function", () => {
      const term = Type.anonymousFunction(
        "dummyArity",
        "dummyClauses",
        "dummyContext",
      );

      assertBoxedTrue(is_function(term));
    });

    it("non-function", () => {
      assertBoxedFalse(is_function(Type.atom("abc")));
    });
  });

  describe("is_function/2", () => {
    const is_function = Erlang["is_function/2"];

    it("function with the given arity", () => {
      const term = Type.anonymousFunction(3, "dummyClauses", "dummyContext");

      assertBoxedTrue(is_function(term, Type.integer(3)));
    });

    it("function with a different arity", () => {
      const term = Type.anonymousFunction(3, "dummyClauses", "dummyContext");

      assertBoxedFalse(is_function(term, Type.integer(4)));
    });

    it("non-function", () => {
      assertBoxedFalse(is_function(Type.atom("abc")));
    });
  });

  describe("is_integer/1", () => {
    const is_integer = Erlang["is_integer/1"];

    it("integer", () => {
      assertBoxedTrue(is_integer(Type.integer(1)));
    });

    it("non-integer", () => {
      assertBoxedFalse(is_integer(Type.atom("abc")));
    });
  });

  describe("is_list/1", () => {
    const is_list = Erlang["is_list/1"];

    it("list", () => {
      const term = Type.list([Type.integer(1), Type.integer(2)]);
      assertBoxedTrue(is_list(term));
    });

    it("non-list", () => {
      assertBoxedFalse(is_list(Type.atom("abc")));
    });
  });

  describe("is_map/1", () => {
    const is_map = Erlang["is_map/1"];

    it("map", () => {
      const term = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ]);

      assertBoxedTrue(is_map(term));
    });

    it("non-map", () => {
      assertBoxedFalse(is_map(Type.atom("abc")));
    });
  });

  describe("is_number/1", () => {
    const is_number = Erlang["is_number/1"];

    it("float", () => {
      assertBoxedTrue(is_number(Type.float(1.0)));
    });

    it("integer", () => {
      assertBoxedTrue(is_number(Type.integer(1)));
    });

    it("non-number", () => {
      assertBoxedFalse(is_number(Type.atom("abc")));
    });
  });

  describe("is_pid/1", () => {
    const is_pid = Erlang["is_pid/1"];

    it("pid", () => {
      const term = Type.pid("my_node@my_host", [0, 11, 222]);
      assertBoxedTrue(is_pid(term));
    });

    it("non-pid", () => {
      assertBoxedFalse(is_pid(Type.atom("abc")));
    });
  });

  describe("is_port/1", () => {
    const is_port = Erlang["is_port/1"];

    it("port", () => {
      const term = Type.port("nonode@nohost", [0, 11]);
      assertBoxedTrue(is_port(term));
    });

    it("non-port", () => {
      assertBoxedFalse(is_port(Type.atom("abc")));
    });
  });

  describe("is_reference/1", () => {
    const is_reference = Erlang["is_reference/1"];

    it("reference", () => {
      const term = Type.reference("nonode@nohost", [0, 1, 2, 3]);
      assertBoxedTrue(is_reference(term));
    });

    it("non-reference", () => {
      assertBoxedFalse(is_reference(Type.atom("abc")));
    });
  });

  describe("is_tuple/1", () => {
    const is_tuple = Erlang["is_tuple/1"];

    it("tuple", () => {
      const term = Type.tuple([Type.integer(1), Type.integer(2)]);
      assertBoxedTrue(is_tuple(term));
    });

    it("non-tuple", () => {
      assertBoxedFalse(is_tuple(Type.atom("abc")));
    });
  });

  describe("length/1", () => {
    const length = Erlang["length/1"];

    it("returns the number of items in the list", () => {
      const term = Type.list([Type.integer(1), Type.integer(2)]);
      assert.deepStrictEqual(length(term), Type.integer(2));
    });

    it("raises ArgumentError if the argument is not a list", () => {
      assertBoxedError(
        () => length(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    });
  });

  describe("list_to_pid/1", () => {
    const fun = Erlang["list_to_pid/1"];

    it("valid textual representation of PID", () => {
      // ~c"<0.11.222>"
      const list = Type.list([
        Type.integer(60),
        Type.integer(48),
        Type.integer(46),
        Type.integer(49),
        Type.integer(49),
        Type.integer(46),
        Type.integer(50),
        Type.integer(50),
        Type.integer(50),
        Type.integer(62),
      ]);

      const result = fun(list);
      const expected = Type.pid("client", [0, 11, 222], "client");

      assert.deepStrictEqual(result, expected);
    });

    it("invalid textual representation of PID", () => {
      // ~c"<0.11>"
      const list = Type.list([
        Type.integer(60),
        Type.integer(48),
        Type.integer(46),
        Type.integer(49),
        Type.integer(49),
        Type.integer(62),
      ]);

      assertBoxedError(
        () => fun(list),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a pid",
        ),
      );
    });

    it("not a list", () => {
      assertBoxedError(
        () => fun(Type.integer(123)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    });

    it("a list that contains a non-integer", () => {
      const list = Type.list([
        Type.integer(60),
        Type.atom("abc"),
        Type.integer(46),
      ]);

      assertBoxedError(
        () => fun(list),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a pid",
        ),
      );
    });

    it("a list that contains an invalid codepoint", () => {
      const list = Type.list([
        Type.integer(60),
        Type.integer(255),
        Type.integer(46),
      ]);

      assertBoxedError(
        () => fun(list),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a pid",
        ),
      );
    });
  });

  describe("list_to_tuple/1", () => {
    const testedFun = Erlang["list_to_tuple/1"];

    it("converts empty list to empty tuple", () => {
      const result = testedFun(Type.list());

      assert.deepStrictEqual(result, Type.tuple([]));
    });

    it("converts non-empty list to tuple", () => {
      const list = Type.list([Type.integer(1), Type.atom("a"), Type.float(3.14)]);
      const result = testedFun(list);

      assert.deepStrictEqual(
        result,
        Type.tuple([Type.integer(1), Type.atom("a"), Type.float(3.14)]),
      );
    });

    it("raises ArgumentError if argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    });

    it("raises ArgumentError if argument is not a proper list", () => {
      const improperList = Type.improperList([Type.integer(1), Type.integer(2), Type.integer(3)]);

      assertBoxedError(
        () => testedFun(improperList),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a proper list"),
      );
    });
  });

  describe("list_to_binary/1", () => {
    const testedFun = Erlang["list_to_binary/1"];

    it("converts empty list to empty binary", () => {
      const result = testedFun(Type.list());

      assert.deepStrictEqual(result, Type.bitstring(""));
    });

    it("converts list of bytes to binary", () => {
      const list = Type.list([Type.integer(72), Type.integer(105)]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.bitstring("Hi"));
    });

    it("converts list with byte values", () => {
      const list = Type.list([Type.integer(65), Type.integer(66), Type.integer(67)]);
      const result = testedFun(list);

      assert.deepStrictEqual(result, Type.bitstring("ABC"));
    });

    it("raises ArgumentError if argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    });

    it("raises ArgumentError if argument is not a proper list", () => {
      const improperList = Type.improperList([Type.integer(65), Type.integer(66)]);

      assertBoxedError(
        () => testedFun(improperList),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a proper list"),
      );
    });

    it("raises ArgumentError if list contains non-integer", () => {
      const list = Type.list([Type.integer(65), Type.atom("abc")]);

      assertBoxedError(
        () => testedFun(list),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a list of bytes"),
      );
    });

    it("raises ArgumentError if list contains negative integer", () => {
      const list = Type.list([Type.integer(-1)]);

      assertBoxedError(
        () => testedFun(list),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a list of bytes"),
      );
    });

    it("raises ArgumentError if list contains integer > 255", () => {
      const list = Type.list([Type.integer(256)]);

      assertBoxedError(
        () => testedFun(list),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a list of bytes"),
      );
    });
  });

  describe("localtime/0", () => {
    const testedFun = Erlang["localtime/0"];

    it("returns current local datetime as {{Year, Month, Day}, {Hour, Minute, Second}}", () => {
      const result = testedFun();
      const now = new Date();

      assert.ok(Type.isTuple(result));
      assert.strictEqual(result.data.length, 2);

      const dateTuple = result.data[0];
      const timeTuple = result.data[1];

      assert.ok(Type.isTuple(dateTuple));
      assert.strictEqual(dateTuple.data.length, 3);
      assert.ok(Type.isTuple(timeTuple));
      assert.strictEqual(timeTuple.data.length, 3);

      // Verify date matches current date
      assert.deepStrictEqual(dateTuple.data[0], Type.integer(BigInt(now.getFullYear())));
      assert.deepStrictEqual(dateTuple.data[1], Type.integer(BigInt(now.getMonth() + 1)));
    });
  });

  describe("convert_time_unit/3", () => {
    const testedFun = Erlang["convert_time_unit/3"];

    it("converts from seconds to milliseconds", () => {
      const result = testedFun(Type.integer(2), Type.atom("second"), Type.atom("millisecond"));
      assert.deepStrictEqual(result, Type.integer(2000));
    });

    it("converts from milliseconds to microseconds", () => {
      const result = testedFun(Type.integer(1), Type.atom("millisecond"), Type.atom("microsecond"));
      assert.deepStrictEqual(result, Type.integer(1000));
    });

    it("raises ArgumentError for non-integer time", () => {
      assertBoxedError(
        () => testedFun(Type.atom("not_int"), Type.atom("second"), Type.atom("millisecond")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    });
  });

  describe("float_to_list/2", () => {
    const testedFun = Erlang["float_to_list/2"];

    it("converts float to list", () => {
      const result = testedFun(Type.float(3.14), Type.list([]));
      assert.ok(Type.isList(result));
      assert.ok(result.data.length > 0);
    });

    it("raises ArgumentError for non-float", () => {
      assertBoxedError(
        () => testedFun(Type.integer(1), Type.list([])),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a float"),
      );
    });
  });

  describe("fun_info/1", () => {
    const testedFun = Erlang["fun_info/1"];

    it("returns function info as list of tuples", () => {
      const fun = Type.anonymousFunction(
        2,
        [],
        Interpreter.buildContext({ module: Type.atom("Elixir.Test"), vars: {} }),
      );
      const result = testedFun(fun);

      assert.ok(Type.isList(result));
      assert.strictEqual(result.data.length, 10);

      // Check that we have an arity tuple
      const arityTuple = result.data.find(t =>
        Type.isTuple(t) && t.data[0].value === "arity"
      );
      assert.ok(arityTuple);
      assert.deepStrictEqual(arityTuple.data[1], Type.integer(2));
    });

    it("raises ArgumentError if argument is not a function", () => {
      assertBoxedError(
        () => testedFun(Type.atom("not_fun")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a function"),
      );
    });
  });

  describe("fun_info/2", () => {
    const testedFun = Erlang["fun_info/2"];

    it("returns arity info", () => {
      const fun = Type.anonymousFunction(
        3,
        [],
        Interpreter.buildContext({ module: Type.atom("Elixir.Test"), vars: {} }),
      );
      const result = testedFun(fun, Type.atom("arity"));
      assert.deepStrictEqual(
        result,
        Type.tuple([Type.atom("arity"), Type.integer(3)]),
      );
    });

    it("returns module info", () => {
      const fun = Type.anonymousFunction(
        1,
        [],
        Interpreter.buildContext({ module: Type.atom("Elixir.Test"), vars: {} }),
      );
      const result = testedFun(fun, Type.atom("module"));
      assert.ok(Type.isTuple(result));
      assert.deepStrictEqual(result.data[0], Type.atom("module"));
    });

    it("raises ArgumentError if first argument is not a function", () => {
      assertBoxedError(
        () => testedFun(Type.atom("not_fun"), Type.atom("arity")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a function"),
      );
    });

    it("raises ArgumentError if second argument is not an atom", () => {
      const fun = Type.anonymousFunction(1, [], Interpreter.buildContext({ module: Type.atom("Elixir.Test"), vars: {} }));
      assertBoxedError(
        () => testedFun(fun, Type.integer(1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    });

    it("raises ArgumentError for invalid item", () => {
      const fun = Type.anonymousFunction(1, [], Interpreter.buildContext({ module: Type.atom("Elixir.Test"), vars: {} }));
      assertBoxedError(
        () => testedFun(fun, Type.atom("invalid_key")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "invalid item"),
      );
    });
  });

  describe("function_exported/3", () => {
    const testedFun = Erlang["function_exported/3"];

    it("returns true for exported function", () => {
      const result = testedFun(
        Type.atom("erlang"),
        Type.atom("abs"),
        Type.integer(1),
      );
      assert.deepStrictEqual(result, Type.boolean(true));
    });

    it("returns false for non-existent function", () => {
      const result = testedFun(
        Type.atom("erlang"),
        Type.atom("nonexistent_func"),
        Type.integer(99),
      );
      assert.deepStrictEqual(result, Type.boolean(false));
    });

    it("returns false for non-existent module", () => {
      const result = testedFun(
        Type.atom("Elixir.NonExistentModule"),
        Type.atom("func"),
        Type.integer(1),
      );
      assert.deepStrictEqual(result, Type.boolean(false));
    });

    it("raises ArgumentError if first argument is not an atom", () => {
      assertBoxedError(
        () => testedFun(Type.integer(1), Type.atom("func"), Type.integer(1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    });

    it("raises ArgumentError if second argument is not an atom", () => {
      assertBoxedError(
        () => testedFun(Type.atom("erlang"), Type.integer(1), Type.integer(1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    });

    it("raises ArgumentError if third argument is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.atom("erlang"), Type.atom("abs"), Type.atom("not_int")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    });
  });

  describe("is_map_key/2", () => {
    const testedFun = Erlang["is_map_key/2"];

    it("returns true when key exists", () => {
      const map = Type.map([[Type.atom("a"), Type.integer(1)]]);
      const result = testedFun(Type.atom("a"), map);
      assert.deepStrictEqual(result, Type.boolean(true));
    });

    it("returns false when key does not exist", () => {
      const map = Type.map([[Type.atom("a"), Type.integer(1)]]);
      const result = testedFun(Type.atom("b"), map);
      assert.deepStrictEqual(result, Type.boolean(false));
    });

    it("raises BadMapError for non-map", () => {
      assertBoxedError(
        () => testedFun(Type.atom("a"), Type.atom("not_map")),
        "BadMapError",
        "expected a map, got: :not_map",
      );
    });
  });

  describe("map_get/2", () => {
    const testedFun = Erlang["map_get/2"];

    it("returns value for existing key", () => {
      const map = Type.map([[Type.atom("key"), Type.integer(42)]]);
      const result = testedFun(Type.atom("key"), map);
      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("raises BadKeyError when key does not exist", () => {
      const map = Type.map([[Type.atom("a"), Type.integer(1)]]);
      assertBoxedError(
        () => testedFun(Type.atom("b"), map),
        "BadKeyError",
        "key :b not found in: %{a: 1}",
      );
    });

    it("raises BadMapError for non-map", () => {
      assertBoxedError(
        () => testedFun(Type.atom("a"), Type.list([])),
        "BadMapError",
        "expected a map, got: []",
      );
    });
  });

  describe("map_size/1", () => {
    const map_size = Erlang["map_size/1"];

    it("returns the number of items in the map", () => {
      const term = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ]);

      assert.deepStrictEqual(map_size(term), Type.integer(2));
    });

    it("raises BadMapError if the argument is not a map", () => {
      assertBoxedError(
        () => map_size(Type.atom("abc")),
        "BadMapError",
        "expected a map, got: :abc",
      );
    });
  });

  describe("make_tuple/2", () => {
    const testedFun = Erlang["make_tuple/2"];

    it("creates empty tuple when size is 0", () => {
      const result = testedFun(Type.integer(0), Type.atom("default"));

      assert.deepStrictEqual(result, Type.tuple([]));
    });

    it("creates tuple of size 1", () => {
      const result = testedFun(Type.integer(1), Type.atom("x"));

      assert.deepStrictEqual(result, Type.tuple([Type.atom("x")]));
    });

    it("creates tuple of size 5 with default value", () => {
      const result = testedFun(Type.integer(5), Type.integer(42));

      assert.deepStrictEqual(
        result,
        Type.tuple([
          Type.integer(42),
          Type.integer(42),
          Type.integer(42),
          Type.integer(42),
          Type.integer(42),
        ]),
      );
    });

    it("works with various default values", () => {
      const result = testedFun(Type.integer(3), Type.list([Type.integer(1), Type.integer(2)]));

      assert.deepStrictEqual(
        result,
        Type.tuple([
          Type.list([Type.integer(1), Type.integer(2)]),
          Type.list([Type.integer(1), Type.integer(2)]),
          Type.list([Type.integer(1), Type.integer(2)]),
        ]),
      );
    });

    it("raises ArgumentError if size is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.integer(1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    });

    it("raises ArgumentError if size is negative", () => {
      assertBoxedError(
        () => testedFun(Type.integer(-1), Type.atom("x")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a valid tuple size"),
      );
    });
  });

  describe("make_fun/3", () => {
    const testedFun = Erlang["make_fun/3"];

    it("creates function reference for exported function", () => {
      const result = testedFun(
        Type.atom("erlang"),
        Type.atom("abs"),
        Type.integer(1),
      );
      assert.ok(Type.isAnonymousFunction(result));
      assert.strictEqual(result.arity, 1);
      assert.deepStrictEqual(result.capturedModule, Type.atom("erlang"));
      assert.deepStrictEqual(result.capturedFunction, Type.atom("abs"));
    });

    it("raises ArgumentError if first argument is not an atom", () => {
      assertBoxedError(
        () => testedFun(Type.integer(1), Type.atom("func"), Type.integer(1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    });

    it("raises ArgumentError if second argument is not an atom", () => {
      assertBoxedError(
        () => testedFun(Type.atom("erlang"), Type.integer(1), Type.integer(1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    });

    it("raises ArgumentError if third argument is not an integer", () => {
      assertBoxedError(
        () => testedFun(Type.atom("erlang"), Type.atom("abs"), Type.atom("not_int")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    });

    it("raises ArgumentError if arity is negative", () => {
      assertBoxedError(
        () => testedFun(Type.atom("erlang"), Type.atom("abs"), Type.integer(-1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not a valid arity"),
      );
    });
  });

  describe("make_ref/0", () => {
    const testedFun = Erlang["make_ref/0"];

    it("creates a reference", () => {
      const result = testedFun();
      assert.ok(Type.isReference(result));
      assert.deepStrictEqual(result.node, Type.atom("nonode@nohost"));
      assert.strictEqual(result.origin, "client");
    });

    it("creates unique references", () => {
      const ref1 = testedFun();
      const ref2 = testedFun();
      // References should be unique (different IDs)
      assert.notStrictEqual(ref1.segments[2], ref2.segments[2]);
    });
  });

  describe("monotonic_time/0", () => {
    const testedFun = Erlang["monotonic_time/0"];

    it("returns an integer", () => {
      const result = testedFun();
      assert.ok(Type.isInteger(result));
      assert.ok(result.value > 0n);
    });
  });

  describe("monotonic_time/1", () => {
    const testedFun = Erlang["monotonic_time/1"];

    it("returns time in specified unit", () => {
      const result = testedFun(Type.atom("millisecond"));
      assert.ok(Type.isInteger(result));
      assert.ok(result.value > 0n);
    });

    it("converts to seconds", () => {
      const result = testedFun(Type.atom("second"));
      assert.ok(Type.isInteger(result));
    });
  });

  describe("not/1", () => {
    const not = Erlang["not/1"];

    it("true", () => {
      assert.deepStrictEqual(not(Type.boolean(true)), Type.boolean(false));
    });

    it("false", () => {
      assert.deepStrictEqual(not(Type.boolean(false)), Type.boolean(true));
    });

    it("not boolean", () => {
      assertBoxedError(() => not(atomAbc), "ArgumentError", "argument error");
    });
  });

  describe("node/0", () => {
    const testedFun = Erlang["node/0"];

    it("returns nonode@nohost for client-side execution", () => {
      const result = testedFun();
      assert.deepStrictEqual(result, Type.atom("nonode@nohost"));
    });
  });

  describe("now/0", () => {
    const testedFun = Erlang["now/0"];

    it("returns {MegaSecs, Secs, MicroSecs} tuple", () => {
      const result = testedFun();

      assert.ok(Type.isTuple(result));
      assert.strictEqual(result.data.length, 3);
      assert.ok(Type.isInteger(result.data[0])); // MegaSecs
      assert.ok(Type.isInteger(result.data[1])); // Secs
      assert.ok(Type.isInteger(result.data[2])); // MicroSecs
    });

    it("returns monotonically increasing values", () => {
      const result1 = testedFun();
      const result2 = testedFun();

      // Second call should be >= first call
      const time1 = result1.data[0].value * 1000000000000n + result1.data[1].value * 1000000n + result1.data[2].value;
      const time2 = result2.data[0].value * 1000000000000n + result2.data[1].value * 1000000n + result2.data[2].value;

      assert.ok(time2 >= time1);
    });
  });

  describe("orelse/2", () => {
    const orelse = Erlang["orelse/2"];

    it("returns true if the first argument is true", () => {
      const context = contextFixture({
        vars: {left: Type.boolean(true), right: Type.atom("abc")},
      });

      const result = orelse(
        (context) => context.vars.left,
        (context) => context.vars.right,
        context,
      );

      assertBoxedTrue(result);
    });

    it("returns the second argument if the first argument is false", () => {
      const context = contextFixture({
        vars: {left: Type.boolean(false), right: Type.atom("abc")},
      });

      const result = orelse(
        (context) => context.vars.left,
        (context) => context.vars.right,
        context,
      );

      assert.deepStrictEqual(result, Type.atom("abc"));
    });

    it("doesn't evaluate the second argument if the first argument is true", () => {
      const result = orelse(
        (_context) => Type.boolean(true),
        (_context) => {
          throw new Error("impossible");
        },
        contextFixture(),
      );

      assertBoxedTrue(result);
    });

    it("raises ArgumentError if the first argument is not a boolean", () => {
      const context = contextFixture({
        vars: {left: Type.nil(), right: Type.boolean(true)},
      });

      assertBoxedError(
        () =>
          orelse(
            (context) => context.vars.left,
            (context) => context.vars.right,
            context,
          ),
        "ArgumentError",
        "argument error: nil",
      );
    });
  });

  describe("phash2/2", () => {
    const testedFun = Erlang["phash2/2"];

    it("returns hash within range", () => {
      const result = testedFun(Type.atom("test"), Type.integer(100));
      assert.ok(Type.isInteger(result));
      assert.ok(result.value >= 0n && result.value < 100n);
    });

    it("returns consistent hash for same input", () => {
      const result1 = testedFun(Type.atom("test"), Type.integer(1000));
      const result2 = testedFun(Type.atom("test"), Type.integer(1000));
      assert.deepStrictEqual(result1, result2);
    });

    it("raises ArgumentError for non-integer range", () => {
      assertBoxedError(
        () => testedFun(Type.atom("test"), Type.atom("not_int")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });

    it("raises ArgumentError for non-positive range", () => {
      assertBoxedError(
        () => testedFun(Type.atom("test"), Type.integer(0)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a positive integer"),
      );
    });
  });

  describe("pid_to_list/1", () => {
    const testedFun = Erlang["pid_to_list/1"];

    it("converts PID to character list", () => {
      const pid = Type.pid(Type.atom("nonode@nohost"), [0, 11, 111], "client");
      const result = testedFun(pid);
      assert.ok(Type.isList(result));
      assert.ok(result.data.length > 0);
      // Check that result starts with '#' 'P' 'I' 'D' '<'
      assert.deepStrictEqual(result.data[0], Type.integer(35)); // '#'
      assert.deepStrictEqual(result.data[1], Type.integer(80)); // 'P'
      assert.deepStrictEqual(result.data[2], Type.integer(73)); // 'I'
      assert.deepStrictEqual(result.data[3], Type.integer(68)); // 'D'
      assert.deepStrictEqual(result.data[4], Type.integer(60)); // '<'
    });

    it("raises ArgumentError for non-PID", () => {
      assertBoxedError(
        () => testedFun(Type.atom("not_pid")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a pid"),
      );
    });
  });

  describe("rem/2", () => {
    const testedFun = Erlang["rem/2"];

    it("returns remainder of positive integers", () => {
      const result = testedFun(Type.integer(10), Type.integer(3));

      assert.deepStrictEqual(result, Type.integer(1));
    });

    it("returns remainder with negative dividend and positive divisor", () => {
      const result = testedFun(Type.integer(-10), Type.integer(3));

      assert.deepStrictEqual(result, Type.integer(-1));
    });

    it("returns remainder with positive dividend and negative divisor", () => {
      const result = testedFun(Type.integer(10), Type.integer(-3));

      assert.deepStrictEqual(result, Type.integer(1));
    });

    it("returns remainder with negative integers", () => {
      const result = testedFun(Type.integer(-10), Type.integer(-3));

      assert.deepStrictEqual(result, Type.integer(-1));
    });

    it("returns 0 when dividend is evenly divisible", () => {
      const result = testedFun(Type.integer(12), Type.integer(4));

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("returns 0 when dividend is 0", () => {
      const result = testedFun(Type.integer(0), Type.integer(5));

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("returns 0 when dividend is 1", () => {
      const result = testedFun(Type.integer(42), Type.integer(1));

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("returns 0 when dividend is -1", () => {
      const result = testedFun(Type.integer(42), Type.integer(-1));

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("raises ArithmeticError when dividend is 0", () => {
      assertBoxedError(
        () => testedFun(Type.integer(5), Type.integer(0)),
        "ArithmeticError",
        "bad argument in arithmetic expression: rem(5, 0)",
      );
    });

    it("raises ArithmeticError if the first argument is a float", () => {
      assertBoxedError(
        () => testedFun(Type.float(5.5), Type.integer(2)),
        "ArithmeticError",
        "bad argument in arithmetic expression: rem(5.5, 2)",
      );
    });

    it("raises ArithmeticError if the second argument is a float", () => {
      assertBoxedError(
        () => testedFun(Type.integer(5), Type.float(2.5)),
        "ArithmeticError",
        "bad argument in arithmetic expression: rem(5, 2.5)",
      );
    });

    it("raises ArithmeticError if the first argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc"), Type.integer(2)),
        "ArithmeticError",
        "bad argument in arithmetic expression: rem(:abc, 2)",
      );
    });

    it("raises ArithmeticError if the second argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.integer(5), Type.atom("abc")),
        "ArithmeticError",
        "bad argument in arithmetic expression: rem(5, :abc)",
      );
    });
  });

  describe("ref_to_list/1", () => {
    const testedFun = Erlang["ref_to_list/1"];

    it("converts reference to character list", () => {
      const ref = Type.reference(Type.atom("nonode@nohost"), [0, 0, 123], "client");
      const result = testedFun(ref);
      assert.ok(Type.isList(result));
      assert.ok(result.data.length > 0);
      // Check that result starts with '#' 'R' 'e' 'f' 'e' 'r' 'e' 'n' 'c' 'e' '<'
      assert.deepStrictEqual(result.data[0], Type.integer(35)); // '#'
      assert.deepStrictEqual(result.data[1], Type.integer(82)); // 'R'
      assert.deepStrictEqual(result.data[2], Type.integer(101)); // 'e'
      assert.deepStrictEqual(result.data[3], Type.integer(102)); // 'f'
    });

    it("raises ArgumentError for non-reference", () => {
      assertBoxedError(
        () => testedFun(Type.atom("not_ref")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a reference"),
      );
    });
  });

  describe("round/1", () => {
    const testedFun = Erlang["round/1"];

    it("returns the integer unchanged", () => {
      const result = testedFun(Type.integer(42));

      assert.deepStrictEqual(result, Type.integer(42));
    });

    it("rounds positive float down when decimal part < 0.5", () => {
      const result = testedFun(Type.float(2.3));

      assert.deepStrictEqual(result, Type.integer(2));
    });

    it("rounds positive float up when decimal part > 0.5", () => {
      const result = testedFun(Type.float(2.7));

      assert.deepStrictEqual(result, Type.integer(3));
    });

    it("rounds positive float up when decimal part = 0.5", () => {
      const result = testedFun(Type.float(2.5));

      assert.deepStrictEqual(result, Type.integer(3));
    });

    it("rounds negative float up when decimal part > -0.5", () => {
      const result = testedFun(Type.float(-2.3));

      assert.deepStrictEqual(result, Type.integer(-2));
    });

    it("rounds negative float down when decimal part < -0.5", () => {
      const result = testedFun(Type.float(-2.7));

      assert.deepStrictEqual(result, Type.integer(-3));
    });

    it("rounds negative float down when decimal part = -0.5", () => {
      const result = testedFun(Type.float(-2.5));

      assert.deepStrictEqual(result, Type.integer(-3));
    });

    it("rounds 0.0 to 0", () => {
      const result = testedFun(Type.float(0.0));

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("rounds -0.0 to 0", () => {
      const result = testedFun(Type.float(-0.0));

      assert.deepStrictEqual(result, Type.integer(0));
    });

    it("raises ArgumentError if argument is not a number", () => {
      assertBoxedError(
        () => testedFun(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    });
  });

  describe("split_binary/2", () => {
    const split_binary = Erlang["split_binary/2"];

    const emptyBitstring = Type.bitstring("");

    it("splits binary at position 0", () => {
      const binary = Type.bitstring("0123456789");
      const position = Type.integer(0);

      const result = split_binary(binary, position);
      const expected = Type.tuple([emptyBitstring, binary]);

      assertBoxedStrictEqual(result, expected);
    });

    it("splits binary at middle position", () => {
      const binary = Type.bitstring("0123456789");
      const position = Type.integer(3);

      const result = split_binary(binary, position);
      const expected = Type.tuple([
        Type.bitstring("012"),
        Type.bitstring("3456789"),
      ]);

      assertBoxedStrictEqual(result, expected);
    });

    it("splits binary at end position", () => {
      const binary = Type.bitstring("0123456789");
      const position = Type.integer(10);

      const result = split_binary(binary, position);
      const expected = Type.tuple([binary, emptyBitstring]);

      assertBoxedStrictEqual(result, expected);
    });

    it("splits empty binary", () => {
      const binary = emptyBitstring;
      const position = Type.integer(0);

      const result = split_binary(binary, position);
      const expected = Type.tuple([emptyBitstring, emptyBitstring]);

      assertBoxedStrictEqual(result, expected);
    });

    it("splits single character binary", () => {
      const binary = Type.bitstring("a");
      const position = Type.integer(1);

      const result = split_binary(binary, position);
      const expected = Type.tuple([binary, emptyBitstring]);

      assertBoxedStrictEqual(result, expected);
    });

    it("splits Unicode binary", () => {
      const binary = Type.bitstring("全息图全息图");
      const position = Type.integer(4);

      const result = split_binary(binary, position);

      const expected = Type.tuple([
        Bitstring.fromBytes([229, 133, 168, 230]),
        Bitstring.fromBytes([
          129, 175, 229, 155, 190, 229, 133, 168, 230, 129, 175, 229, 155, 190,
        ]),
      ]);

      assertBoxedStrictEqual(result, expected);
    });

    it("raises ArgumentError if the first argument is not a binary", () => {
      assertBoxedError(
        () => split_binary(Type.atom("abc"), Type.integer(1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("raises ArgumentError if the first argument is a non-binary bitstring", () => {
      assertBoxedError(
        () => split_binary(Type.bitstring([1, 0, 1]), Type.integer(1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("raises ArgumentError if the second argument is not an integer", () => {
      assertBoxedError(
        () => split_binary(Type.bitstring("abc"), Type.atom("invalid")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });

    it("raises ArgumentError if the second argument is a negative integer", () => {
      assertBoxedError(
        () => split_binary(Type.bitstring("abc"), Type.integer(-1)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });

    it("raises ArgumentError if position is greater than binary size", () => {
      assertBoxedError(
        () => split_binary(Type.bitstring("abc"), Type.integer(4)),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });
  });

  describe("tl/1", () => {
    const tl = Erlang["tl/1"];

    describe("proper list", () => {
      it("1 item", () => {
        const list = Type.list([Type.integer(1)]);
        const result = tl(list);
        const expected = Type.list();

        assert.deepStrictEqual(result, expected);
      });

      it("2 items", () => {
        const list = Type.list([Type.integer(1), Type.integer(2)]);
        const result = tl(list);
        const expected = Type.list([Type.integer(2)]);

        assert.deepStrictEqual(result, expected);
      });

      it("3 items", () => {
        const list = Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        const result = tl(list);
        const expected = Type.list([Type.integer(2), Type.integer(3)]);

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("improper list", () => {
      it("2 items", () => {
        const list = Type.improperList([Type.integer(1), Type.integer(2)]);
        const result = tl(list);
        const expected = Type.integer(2);

        assert.deepStrictEqual(result, expected);
      });

      it("3 items", () => {
        const list = Type.improperList([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        const result = tl(list);
        const expected = Type.improperList([Type.integer(2), Type.integer(3)]);

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("errors", () => {
      it("raises ArgumentError if the argument is an empty boxed list", () => {
        assertBoxedError(
          () => tl(Type.list()),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a nonempty list"),
        );
      });

      it("raises ArgumentError if the argument is not a boxed list", () => {
        assertBoxedError(
          () => tl(Type.integer(123)),
          "ArgumentError",
          Interpreter.buildArgumentErrorMsg(1, "not a nonempty list"),
        );
      });
    });
  });

  describe("tuple_to_list/1", () => {
    const tuple_to_list = Erlang["tuple_to_list/1"];

    it("returns a list corresponding to the given tuple", () => {
      const data = [Type.integer(1), Type.integer(2), Type.integer(3)];
      const tuple = Type.tuple(data);

      const result = tuple_to_list(tuple);
      const expected = Type.list(data);

      assert.deepStrictEqual(result, expected);
    });

    it("raises ArgumentError if the argument is not a tuple", () => {
      assertBoxedError(
        () => tuple_to_list(Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a tuple"),
      );
    });
  });

  describe("system_time/0", () => {
    const testedFun = Erlang["system_time/0"];

    it("returns an integer representing system time", () => {
      const result = testedFun();
      assert.ok(Type.isInteger(result));
      assert.ok(result.value > 0n);
    });

    it("returns monotonically increasing values", () => {
      const time1 = testedFun();
      const time2 = testedFun();
      assert.ok(time2.value >= time1.value);
    });
  });

  describe("system_time/1", () => {
    const testedFun = Erlang["system_time/1"];

    it("returns system time in specified unit", () => {
      const result = testedFun(Type.atom("second"));
      assert.ok(Type.isInteger(result));
      assert.ok(result.value > 0n);
    });

    it("converts to milliseconds", () => {
      const result = testedFun(Type.atom("millisecond"));
      assert.ok(Type.isInteger(result));
      assert.ok(result.value > 0n);
    });
  });

  describe("time/0", () => {
    const testedFun = Erlang["time/0"];

    it("returns current time as {Hour, Minute, Second}", () => {
      const result = testedFun();

      assert.ok(Type.isTuple(result));
      assert.strictEqual(result.data.length, 3);
      assert.ok(Type.isInteger(result.data[0]));
      assert.ok(Type.isInteger(result.data[1]));
      assert.ok(Type.isInteger(result.data[2]));

      // Verify hour is in valid range
      assert.ok(result.data[0].value >= 0n && result.data[0].value <= 23n);
      assert.ok(result.data[1].value >= 0n && result.data[1].value <= 59n);
      assert.ok(result.data[2].value >= 0n && result.data[2].value <= 59n);
    });
  });

  describe("timestamp/0", () => {
    const testedFun = Erlang["timestamp/0"];

    it("returns {MegaSecs, Secs, MicroSecs} tuple", () => {
      const result = testedFun();

      assert.ok(Type.isTuple(result));
      assert.strictEqual(result.data.length, 3);
      assert.ok(Type.isInteger(result.data[0]));
      assert.ok(Type.isInteger(result.data[1]));
      assert.ok(Type.isInteger(result.data[2]));
    });
  });

  describe("unique_integer/0", () => {
    const testedFun = Erlang["unique_integer/0"];

    it("returns a unique integer", () => {
      const result1 = testedFun();
      const result2 = testedFun();

      assert.ok(Type.isInteger(result1));
      assert.ok(Type.isInteger(result2));
      assert.notStrictEqual(result1.value, result2.value);
    });

    it("returns monotonically increasing values", () => {
      const result1 = testedFun();
      const result2 = testedFun();

      assert.ok(result2.value > result1.value);
    });
  });

  describe("unique_integer/1", () => {
    const testedFun = Erlang["unique_integer/1"];

    it("returns unique integer with no modifiers", () => {
      const result = testedFun(Type.list([]));
      assert.ok(Type.isInteger(result));
    });

    it("returns positive integer with positive modifier", () => {
      const result = testedFun(Type.list([Type.atom("positive")]));
      assert.ok(Type.isInteger(result));
      assert.ok(result.value > 0n);
    });

    it("returns unique integers with monotonic modifier", () => {
      const result1 = testedFun(Type.list([Type.atom("monotonic")]));
      const result2 = testedFun(Type.list([Type.atom("monotonic")]));
      assert.ok(result2.value > result1.value);
    });

    it("handles both positive and monotonic modifiers", () => {
      const result = testedFun(Type.list([Type.atom("positive"), Type.atom("monotonic")]));
      assert.ok(Type.isInteger(result));
      assert.ok(result.value > 0n);
    });

    it("raises ArgumentError for invalid modifier", () => {
      assertBoxedError(
        () => testedFun(Type.list([Type.atom("invalid")])),
        "ArgumentError",
        "badarg: invalid modifier :invalid",
      );
    });

    it("raises ArgumentError if argument is not a list", () => {
      assertBoxedError(
        () => testedFun(Type.atom("not_list")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    });
  });

  describe("universaltime/0", () => {
    const testedFun = Erlang["universaltime/0"];

    it("returns current UTC datetime as {{Year, Month, Day}, {Hour, Minute, Second}}", () => {
      const result = testedFun();
      const now = new Date();

      assert.ok(Type.isTuple(result));
      assert.strictEqual(result.data.length, 2);

      const dateTuple = result.data[0];
      const timeTuple = result.data[1];

      assert.ok(Type.isTuple(dateTuple));
      assert.strictEqual(dateTuple.data.length, 3);
      assert.ok(Type.isTuple(timeTuple));
      assert.strictEqual(timeTuple.data.length, 3);

      // Verify UTC date matches
      assert.deepStrictEqual(dateTuple.data[0], Type.integer(BigInt(now.getUTCFullYear())));
      assert.deepStrictEqual(dateTuple.data[1], Type.integer(BigInt(now.getUTCMonth() + 1)));
    });
  });
});
