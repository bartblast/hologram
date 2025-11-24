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
const atomC = Type.atom("c");
const float1 = Type.float(1.0);
const float2 = Type.float(2.0);
const float3 = Type.float(3.0);
const float5 = Type.float(5.0);
const float6 = Type.float(6.0);
const integer0 = Type.integer(0);
const integer1 = Type.integer(1);
const integer2 = Type.integer(2);
const integer3 = Type.integer(3);
const integer4 = Type.integer(4);
const integer5 = Type.integer(5);
const integer6 = Type.integer(6);
const integer11 = Type.integer(11);
const integer15 = Type.integer(15);
const list1 = Type.list([integer1, integer2]);

const mapA1B2 = Type.map([
  [atomA, integer1],
  [atomB, integer2],
]);

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

  describe("band/2", () => {
    const testedFun = Erlang["band/2"];

    it("valid arguments", () => {
      // 5 = 0b0101, 3 = 0b0011, 1 = 0b0001
      const result = testedFun(integer5, integer3);

      assert.deepStrictEqual(result, integer1);
    });

    it("both arguments are zero", () => {
      const result = testedFun(integer0, integer0);

      assert.deepStrictEqual(result, integer0);
    });

    it("left argument is zero", () => {
      const result = testedFun(integer0, integer5);

      assert.deepStrictEqual(result, integer0);
    });

    it("right argument is zero", () => {
      const result = testedFun(integer5, integer0);

      assert.deepStrictEqual(result, integer0);
    });

    it("left argument is negative", () => {
      const left = Type.integer(-5);

      // 15 = 0b1111, 11 = -5 = 0b1011
      const result = testedFun(left, integer15);

      assert.deepStrictEqual(result, integer11);
    });

    it("right argument is negative", () => {
      const right = Type.integer(-5);

      // 15 = 0b1111, 11 = -5 = 0b1011
      const result = testedFun(integer15, right);

      assert.deepStrictEqual(result, integer11);
    });

    it("works with large numbers", () => {
      // Number.MAX_SAFE_INTEGER = 9007199254740991
      // = 0b11111111111111111111111111111111111111111111111111111
      //
      // 2 * 9007199254740991 = 18014398509481983
      // = 0b111111111111111111111111111111111111111111111111111111
      //
      // 18014398509481982 = 0b111111111111111111111111111111111111111111111111111110

      const left = Type.integer(18014398509481983n);
      const right = Type.integer(18014398509481982n);

      const result = testedFun(left, right);

      assert.deepStrictEqual(result, right);
    });

    it("raises ArithmeticError if the first argument is not an integer", () => {
      assertBoxedError(
        () => testedFun(float5, integer3),
        "ArithmeticError",
        "bad argument in arithmetic expression: Bitwise.band(5.0, 3)",
      );
    });

    it("raises ArithmeticError if the second argument is not an integer", () => {
      assertBoxedError(
        () => testedFun(integer5, float3),
        "ArithmeticError",
        "bad argument in arithmetic expression: Bitwise.band(5, 3.0)",
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

  describe("binary_to_float/1", () => {
    const binary_to_float = Erlang["binary_to_float/1"];

    it("positive float without sign in decimal notation", () => {
      const input = Type.bitstring("1.23");
      const result = binary_to_float(input);

      assert.deepStrictEqual(result, Type.float(1.23));
    });

    it("positive float with sign in decimal notation", () => {
      const input = Type.bitstring("+1.23");
      const result = binary_to_float(input);

      assert.deepStrictEqual(result, Type.float(1.23));
    });

    it("negative float in decimal notation", () => {
      const input = Type.bitstring("-1.23");
      const result = binary_to_float(input);

      assert.deepStrictEqual(result, Type.float(-1.23));
    });

    it("unsigned zero float in decimal notation", () => {
      const input = Type.bitstring("0.0");
      const result = binary_to_float(input);

      assert.deepStrictEqual(result, Type.float(0.0));
    });

    it("signed positive zero float in decimal notation", () => {
      const input = Type.bitstring("+0.0");
      const result = binary_to_float(input);

      assert.deepStrictEqual(result, Type.float(+0.0));
    });

    it("signed negative zero float in decimal notation", () => {
      const input = Type.bitstring("-0.0");
      const result = binary_to_float(input);

      assert.deepStrictEqual(result, Type.float(-0.0));
    });

    it("positive float in scientific notation", () => {
      const input = Type.bitstring("1.23456e+3");
      const result = binary_to_float(input);

      assert.deepStrictEqual(result, Type.float(1234.56));
    });

    it("negative float in scientific notation", () => {
      const input = Type.bitstring("-1.23456e+3");
      const result = binary_to_float(input);

      assert.deepStrictEqual(result, Type.float(-1234.56));
    });

    it("unsigned zero float in scientific notation", () => {
      const input = Type.bitstring("0.0e+1");
      const result = binary_to_float(input);

      assert.deepStrictEqual(result, Type.float(0.0));
    });

    it("signed positive zero float in scientific notation", () => {
      const input = Type.bitstring("+0.0e+1");
      const result = binary_to_float(input);

      assert.deepStrictEqual(result, Type.float(+0.0));
    });

    it("signed negative zero float in scientific notation", () => {
      const input = Type.bitstring("-0.0e+1");
      const result = binary_to_float(input);

      assert.deepStrictEqual(result, Type.float(-0.0));
    });

    it("positive integer", () => {
      const input = Type.bitstring("123");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    });

    it("negative integer", () => {
      const input = Type.bitstring("-123");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    });

    it("zero integer", () => {
      const input = Type.bitstring("0");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    });

    it("with leading zeros", () => {
      const input = Type.bitstring("00012.34");
      const result = binary_to_float(input);

      assert.deepStrictEqual(result, Type.float(12.34));
    });

    it("uppercase scientific notation", () => {
      const input = Type.bitstring("1.23456E3");
      const result = binary_to_float(input);

      assert.deepStrictEqual(result, Type.float(1234.56));
    });

    it("negative exponent", () => {
      const input = Type.bitstring("1.23e-3");
      const result = binary_to_float(input);

      assert.deepStrictEqual(result, Type.float(0.00123));
    });

    it("non-binary bitstring input", () => {
      const input = Bitstring.fromBits([1, 0, 1]);

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("non-bitstring input", () => {
      const input = Type.atom("abc");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    });

    it("with underscore", () => {
      const input = Type.bitstring("1_000.5");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    });

    it("invalid float format", () => {
      const input = Type.bitstring("12.3.4");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    });

    it("non-numeric text", () => {
      const input = Type.bitstring("abc");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    });

    it("empty input", () => {
      const input = Type.bitstring("");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    });

    it("decimal point only", () => {
      const input = Type.bitstring(".");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    });

    it("with leading dot", () => {
      const input = Type.bitstring(".5");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    });

    it("with trailing dot", () => {
      const input = Type.bitstring("5.");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    });

    it("scientific notation without the fractional part", () => {
      const input = Type.bitstring("3e10");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    });

    it("with trailing exponent marker", () => {
      const input = Type.bitstring("2e");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    });

    it("with leading whitespace", () => {
      const input = Type.bitstring(" 12.3");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    });

    it("with trailing whitespace", () => {
      const input = Type.bitstring("12.3 ");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    });

    it("with multiple exponent markers", () => {
      const input = Type.bitstring("1e2e3");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    });

    it("Infinity text", () => {
      const input = Type.bitstring("Infinity");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    });

    it("hex-style JS float", () => {
      const input = Type.bitstring("0x1.fp2");

      assertBoxedError(
        () => binary_to_float(input),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
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

    it("rounds positive float with fractional part up", () => {
      const result = testedFun(Type.float(1.23));

      assert.deepStrictEqual(result, integer2);
    });

    it("rounds negative float with fractional part up toward zero", () => {
      const result = testedFun(Type.float(-1.23));
      const expected = Type.integer(-1);

      assert.deepStrictEqual(result, expected);
    });

    it("keeps positive float without fractional part unchanged", () => {
      const result = testedFun(Type.float(1.0));

      assert.deepStrictEqual(result, integer1);
    });

    it("keeps negative float without fractional part unchanged", () => {
      const result = testedFun(Type.float(-1.0));
      const expected = Type.integer(-1);

      assert.deepStrictEqual(result, expected);
    });

    it("keeps signed negative zero float unchanged", () => {
      const result = testedFun(Type.float(-0.0));

      assert.deepStrictEqual(result, integer0);
    });

    it("keeps signed positive zero float unchanged", () => {
      const result = testedFun(Type.float(+0.0));

      assert.deepStrictEqual(result, integer0);
    });

    it("keeps unsigned zero float unchanged", () => {
      const result = testedFun(Type.float(0.0));

      assert.deepStrictEqual(result, integer0);
    });

    it("keeps positive integer unchanged", () => {
      const result = testedFun(integer1);

      assert.deepStrictEqual(result, integer1);
    });

    it("keeps negative integer unchanged", () => {
      const integer = Type.integer(-1);
      const result = testedFun(integer);

      assert.deepStrictEqual(result, integer);
    });

    it("keeps zero integer unchanged", () => {
      const result = testedFun(integer0);

      assert.deepStrictEqual(result, integer0);
    });

    it("raises ArgumentError if the argument is not a number", () => {
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

  describe("insert_element/3", () => {
    const insert_element = Erlang["insert_element/3"];

    it("inserts the given value into an empty tuple", () => {
      const result = insert_element(integer1, Type.tuple(), atomA);

      assert.deepStrictEqual(result, Type.tuple([atomA]));
    });

    it("inserts the given value at the beginning of a one-element tuple", () => {
      const result = insert_element(integer1, Type.tuple([integer1]), atomA);

      assert.deepStrictEqual(result, Type.tuple([atomA, integer1]));
    });

    it("inserts the given value at the end of a one-element tuple", () => {
      const result = insert_element(integer2, Type.tuple([integer1]), atomA);

      assert.deepStrictEqual(result, Type.tuple([integer1, atomA]));
    });

    it("inserts the given value at the beginning of a multi-element tuple", () => {
      const result = insert_element(integer1, tuple2, atomA);

      assert.deepStrictEqual(result, Type.tuple([atomA, integer1, integer2]));
    });

    it("inserts the given value into the middle of a multi-element tuple", () => {
      const result = insert_element(integer2, tuple2, atomA);

      assert.deepStrictEqual(result, Type.tuple([integer1, atomA, integer2]));
    });

    it("inserts the given value at the end of a multi-element tuple", () => {
      const result = insert_element(integer3, tuple2, atomA);

      assert.deepStrictEqual(result, Type.tuple([integer1, integer2, atomA]));
    });

    it("raises ArgumentError if the first argument is not an integer", () => {
      assertBoxedError(
        () => insert_element(atomB, tuple2, atomA),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    });

    it("raises ArgumentError if the second argument is not a tuple", () => {
      assertBoxedError(
        () => insert_element(integer1, atomB, atomA),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a tuple"),
      );
    });

    it("raises ArgumentError if the index is larger than the size of the tuple plus one", () => {
      assertBoxedError(
        () => insert_element(integer4, tuple2, atomA),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    });

    it("raises ArgumentError if the index is not positive", () => {
      assertBoxedError(
        () => insert_element(integer0, tuple2, atomA),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
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

  describe("is_map_key/2", () => {
    const is_map_key = Erlang["is_map_key/2"];

    it("returns true if the given map has the given key", () => {
      assertBoxedTrue(is_map_key(atomB, mapA1B2));
    });

    it("returns false if the given map doesn't have the given key", () => {
      assertBoxedFalse(is_map_key(atomC, mapA1B2));
    });

    it("raises BadMapError if the second argument is not a map", () => {
      assertBoxedError(
        () => is_map_key(atomA, atomAbc),
        "BadMapError",
        "expected a map, got: :abc",
      );
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

  describe("make_tuple/2", () => {
    const make_tuple = Erlang["make_tuple/2"];

    it("creates tuple of the given size with all elements set to the given value", () => {
      const tuple = make_tuple(integer3, atomA);

      assert.deepStrictEqual(tuple, Type.tuple([atomA, atomA, atomA]));
    });

    it("creates an empty tuple when arity is zero", () => {
      const tuple = make_tuple(integer0, atomA);

      assert.deepStrictEqual(tuple, Type.tuple());
    });

    it("raises ArgumentError when arity is negative", () => {
      assertBoxedError(
        () => make_tuple(Type.integer(-1), atomA),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    });

    it("raises ArgumentError when arity is not an integer", () => {
      assertBoxedError(
        () => make_tuple(float2, atomA),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
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

  describe("setelement/3", () => {
    const setelement = Erlang["setelement/3"];

    it("replaces a middle element", () => {
      const result = setelement(integer2, tuple3, atomA);

      assert.deepStrictEqual(result, Type.tuple([integer1, atomA, integer3]));
    });

    it("replaces the first element", () => {
      const result = setelement(integer1, tuple2, atomA);

      assert.deepStrictEqual(result, Type.tuple([atomA, integer2]));
    });

    it("replaces the last element", () => {
      const result = setelement(integer2, tuple2, atomA);

      assert.deepStrictEqual(result, Type.tuple([integer1, atomA]));
    });

    it("raises ArgumentError if the first argument is not an integer", () => {
      assertBoxedError(
        () => setelement(atomB, tuple2, atomA),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    });

    it("raises ArgumentError if the second argument is not a tuple", () => {
      assertBoxedError(
        () => setelement(integer1, atomB, atomA),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a tuple"),
      );
    });

    it("raises ArgumentError if the index is larger than the size of the tuple", () => {
      assertBoxedError(
        () => setelement(integer3, tuple2, atomA),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    });

    it("raises ArgumentError if the index is not positive", () => {
      assertBoxedError(
        () => setelement(integer0, tuple2, atomA),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
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
});
