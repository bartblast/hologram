"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedFalse,
  assertBoxedTrue,
  contextFixture,
  linkModules,
  unlinkModules,
} from "../support/helpers.mjs";

import Erlang from "../../../assets/js/erlang/erlang.mjs";
import HologramInterpreterError from "../../../assets/js/errors/interpreter_error.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

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
const pid1 = Type.pid("my_node@my_host", [0, 11, 111]);
const pid2 = Type.pid("my_node@my_host", [0, 11, 112]);
const tuple2 = Type.tuple([Type.integer(1), Type.integer(2)]);
const tuple3 = Type.tuple([Type.integer(1), Type.integer(2), Type.integer(3)]);

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/erlang_test.exs
// Always update both together.

describe("*/2", () => {
  const fun = Erlang["*/2"];

  it("float * float", () => {
    assert.deepStrictEqual(fun(float2, float3), float6);
  });

  it("float * integer", () => {
    assert.deepStrictEqual(fun(float3, integer2), float6);
  });

  it("integer * float", () => {
    assert.deepStrictEqual(fun(integer2, float3), float6);
  });

  it("integer * integer", () => {
    assert.deepStrictEqual(fun(integer2, integer3), integer6);
  });

  it("raises ArithmeticError if the first argument is not a number", () => {
    assertBoxedError(
      () => fun(atomA, integer1),
      "ArithmeticError",
      "bad argument in arithmetic expression",
    );
  });

  it("raises ArithmeticError if the second argument is not a number", () => {
    assertBoxedError(
      () => fun(integer1, atomA),
      "ArithmeticError",
      "bad argument in arithmetic expression",
    );
  });
});

describe("+/2", () => {
  const fun = Erlang["+/2"];

  it("float + float", () => {
    assert.deepStrictEqual(fun(float1, float2), float3);
  });

  it("float + integer", () => {
    assert.deepStrictEqual(fun(float1, integer2), float3);
  });

  it("integer + float", () => {
    assert.deepStrictEqual(fun(integer1, float2), float3);
  });

  it("integer + integer", () => {
    assert.deepStrictEqual(fun(integer1, integer2), integer3);
  });

  it("raises ArithmeticError if the first argument is not a number", () => {
    assertBoxedError(
      () => fun(atomA, integer1),
      "ArithmeticError",
      "bad argument in arithmetic expression",
    );
  });

  it("raises ArithmeticError if the second argument is not a number", () => {
    assertBoxedError(
      () => fun(integer1, atomA),
      "ArithmeticError",
      "bad argument in arithmetic expression",
    );
  });
});

describe("++/2", () => {
  const fun = Erlang["++/2"];

  it("concatenates a proper non-empty list and another proper non-empty list", () => {
    const left = Type.list([Type.integer(1), Type.integer(2)]);
    const right = Type.list([Type.integer(3), Type.integer(4)]);

    const result = fun(left, right);

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

    const result = fun(left, right);

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

    const result = fun(left, right);

    const expected = Type.improperList([
      Type.integer(1),
      Type.integer(2),
      Type.integer(3),
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("first list is empty", () => {
    const left = Type.list([]);
    const right = Type.list([Type.integer(1), Type.integer(2)]);

    const result = fun(left, right);
    const expected = Type.list([Type.integer(1), Type.integer(2)]);

    assert.deepStrictEqual(result, expected);
  });

  it("second list is empty", () => {
    const left = Type.list([Type.integer(1), Type.integer(2)]);
    const right = Type.list([]);

    const result = fun(left, right);
    const expected = Type.list([Type.integer(1), Type.integer(2)]);

    assert.deepStrictEqual(result, expected);
  });

  it("raises ArgumentError if the first argument is not a list", () => {
    assertBoxedError(
      () => fun(atomAbc, Type.list([])),
      "ArgumentError",
      "argument error",
    );
  });

  it("raises ArgumentError if the first argument is an improper list", () => {
    assertBoxedError(
      () =>
        fun(
          Type.improperList([Type.integer(1), Type.integer(2)]),
          Type.list([]),
        ),
      "ArgumentError",
      "argument error",
    );
  });
});

describe("-/2", () => {
  const fun = Erlang["-/2"];

  it("float - float", () => {
    assert.deepStrictEqual(fun(float3, float2), float1);
  });

  it("float - integer", () => {
    assert.deepStrictEqual(fun(float3, integer2), float1);
  });

  it("integer - float", () => {
    assert.deepStrictEqual(fun(integer3, float2), float1);
  });

  it("integer - integer", () => {
    assert.deepStrictEqual(fun(integer3, integer2), integer1);
  });

  it("raises ArithmeticError if the first argument is not a number", () => {
    assertBoxedError(
      () => fun(atomA, integer1),
      "ArithmeticError",
      "bad argument in arithmetic expression",
    );
  });

  it("raises ArithmeticError if the second argument is not a number", () => {
    assertBoxedError(
      () => fun(integer1, atomA),
      "ArithmeticError",
      "bad argument in arithmetic expression",
    );
  });
});

describe("--/2", () => {
  const fun = Erlang["--/2"];

  it("there are no matching elems", () => {
    const left = Type.list([Type.integer(1), Type.integer(2)]);
    const right = Type.list([Type.integer(3), Type.integer(4)]);

    assert.deepStrictEqual(fun(left, right), left);
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

    assert.deepStrictEqual(fun(left, right), expected);
  });

  it("first list is empty", () => {
    const left = Type.list([]);
    const right = Type.list([Type.integer(1), Type.integer(2)]);

    assert.deepStrictEqual(fun(left, right), left);
  });

  it("second list is empty", () => {
    const left = Type.list([Type.integer(1), Type.integer(2)]);
    const right = Type.list([]);

    assert.deepStrictEqual(fun(left, right), left);
  });

  it("first arg is not a list", () => {
    assertBoxedError(
      () =>
        fun(Type.atom("abc"), Type.list([Type.integer(1), Type.integer(2)])),
      "ArgumentError",
      "argument error",
    );
  });

  it("second arg is not a list", () => {
    assertBoxedError(
      () =>
        fun(Type.list([Type.integer(1), Type.integer(2)]), Type.atom("abc")),
      "ArgumentError",
      "argument error",
    );
  });
});

describe("//2", () => {
  const fun = Erlang["//2"];

  it("divides float by float", () => {
    assert.deepStrictEqual(
      fun(Type.float(3.0), Type.float(2.0)),
      Type.float(1.5),
    );
  });

  it("divides integer by integer", () => {
    assert.deepStrictEqual(
      fun(Type.integer(3), Type.integer(2)),
      Type.float(1.5),
    );
  });

  it("first arg is not a number", () => {
    assertBoxedError(
      () => fun(Type.atom("abc"), Type.integer(3)),
      "ArithmeticError",
      "bad argument in arithmetic expression",
    );
  });

  it("second arg is not a number", () => {
    assertBoxedError(
      () => fun(Type.integer(3), Type.atom("abc")),
      "ArithmeticError",
      "bad argument in arithmetic expression",
    );
  });

  it("second arg is equal to (float) 0.0", () => {
    assertBoxedError(
      () => fun(Type.integer(1), Type.float(0.0)),
      "ArithmeticError",
      "bad argument in arithmetic expression",
    );
  });

  it("second arg is equal to (integer) 0", () => {
    assertBoxedError(
      () => fun(Type.integer(1), Type.integer(0)),
      "ArithmeticError",
      "bad argument in arithmetic expression",
    );
  });
});

describe("/=/2", () => {
  const fun = Erlang["/=/2"];

  it("atom == atom", () => {
    assertBoxedFalse(fun(atomA, atomA));
  });

  it("float == float", () => {
    assertBoxedFalse(fun(float1, float1));
  });

  it("float == integer", () => {
    assertBoxedFalse(fun(float1, integer1));
  });

  it("integer == float", () => {
    assertBoxedFalse(fun(integer1, float1));
  });

  it("integer == integer", () => {
    assertBoxedFalse(fun(integer1, integer1));
  });

  it("pid == pid", () => {
    assertBoxedFalse(fun(pid1, pid1));
  });

  it("tuple == tuple", () => {
    assertBoxedFalse(fun(tuple3, tuple3));
  });

  it("atom < atom", () => {
    assertBoxedTrue(fun(atomA, atomB));
  });

  it("float < atom (always)", () => {
    assertBoxedTrue(fun(float1, atomA));
  });

  it("float < float", () => {
    assertBoxedTrue(fun(float1, float2));
  });

  it("float < integer", () => {
    assertBoxedTrue(fun(float1, integer2));
  });

  it("integer < atom (always)", () => {
    assertBoxedTrue(fun(integer1, atomA));
  });

  it("integer < float", () => {
    assertBoxedTrue(fun(integer1, float2));
  });

  it("integer < integer", () => {
    assertBoxedTrue(fun(integer1, integer2));
  });

  it("pid < pid", () => {
    assertBoxedTrue(fun(pid1, pid2));
  });

  it("pid < tuple (always)", () => {
    assertBoxedTrue(fun(pid1, tuple2));
  });

  it("tuple < tuple", () => {
    assertBoxedTrue(fun(tuple2, tuple3));
  });

  it("atom > atom", () => {
    assertBoxedTrue(fun(atomB, atomA));
  });

  it("float > float", () => {
    assertBoxedTrue(fun(float2, float1));
  });

  it("float > integer", () => {
    assertBoxedTrue(fun(float2, integer1));
  });

  it("integer > float", () => {
    assertBoxedTrue(fun(integer2, float1));
  });

  it("integer > integer", () => {
    assertBoxedTrue(fun(integer2, integer1));
  });

  it("pid > pid", () => {
    assertBoxedTrue(fun(pid2, pid1));
  });

  it("tuple > tuple", () => {
    assertBoxedTrue(fun(tuple3, tuple2));
  });

  // TODO: reference, function, port, map, list, bitstring
});

describe("</2", () => {
  const fun = Erlang["</2"];

  it("atom == atom", () => {
    assertBoxedFalse(fun(atomA, atomA));
  });

  it("float == float", () => {
    assertBoxedFalse(fun(float1, float1));
  });

  it("float == integer", () => {
    assertBoxedFalse(fun(float1, integer1));
  });

  it("integer == float", () => {
    assertBoxedFalse(fun(integer1, float1));
  });

  it("integer == integer", () => {
    assertBoxedFalse(fun(integer1, integer1));
  });

  it("pid == pid", () => {
    assertBoxedFalse(fun(pid1, pid1));
  });

  it("tuple == tuple", () => {
    assertBoxedFalse(fun(tuple3, tuple3));
  });

  it("atom < atom", () => {
    assertBoxedTrue(fun(atomA, atomB));
  });

  it("float < atom (always)", () => {
    assertBoxedTrue(fun(float1, atomA));
  });

  it("float < float", () => {
    assertBoxedTrue(fun(float1, float2));
  });

  it("float < integer", () => {
    assertBoxedTrue(fun(float1, integer2));
  });

  it("integer < atom (always)", () => {
    assertBoxedTrue(fun(integer1, atomA));
  });

  it("integer < float", () => {
    assertBoxedTrue(fun(integer1, float2));
  });

  it("integer < integer", () => {
    assertBoxedTrue(fun(integer1, integer2));
  });

  it("pid < pid", () => {
    assertBoxedTrue(fun(pid1, pid2));
  });

  it("pid < tuple (always)", () => {
    assertBoxedTrue(fun(pid1, tuple3));
  });

  it("tuple < tuple", () => {
    assertBoxedTrue(fun(tuple2, tuple3));
  });

  it("atom > atom", () => {
    assertBoxedFalse(fun(atomB, atomA));
  });

  it("float > float", () => {
    assertBoxedFalse(fun(float2, float1));
  });

  it("float > integer", () => {
    assertBoxedFalse(fun(float2, integer1));
  });

  it("integer > float", () => {
    assertBoxedFalse(fun(integer2, float1));
  });

  it("integer > integer", () => {
    assertBoxedFalse(fun(integer2, integer1));
  });

  it("pid > pid", () => {
    assertBoxedFalse(fun(pid2, pid1));
  });

  it("tuple > tuple", () => {
    assertBoxedFalse(fun(tuple3, tuple2));
  });

  it("throws a not yet implemented error when the left argument type is not yet supported", () => {
    const expectedMessage =
      'Structural comparison currently supports only atoms, floats, integers, pids and tuples, got: "abc"';

    assert.throw(
      () => fun(Type.bitstring("abc"), integer1),
      HologramInterpreterError,
      expectedMessage,
    );
  });

  it("throws a not yet implemented error when the right argument type is not yet supported", () => {
    const expectedMessage =
      'Structural comparison currently supports only atoms, floats, integers, pids and tuples, got: "abc"';

    assert.throw(
      () => fun(integer1, Type.bitstring("abc")),
      HologramInterpreterError,
      expectedMessage,
    );
  });

  // TODO: reference, function, port, map, list, bitstring
});

describe("=/=/2", () => {
  const fun = Erlang["=/=/2"];

  it("atom == atom", () => {
    assertBoxedFalse(fun(atomA, atomA));
  });

  it("float == float", () => {
    assertBoxedFalse(fun(float1, float1));
  });

  it("float == integer", () => {
    assertBoxedTrue(fun(float1, integer1));
  });

  it("integer == float", () => {
    assertBoxedTrue(fun(integer1, float1));
  });

  it("integer == integer", () => {
    assertBoxedFalse(fun(integer1, integer1));
  });

  it("pid == pid", () => {
    assertBoxedFalse(fun(pid1, pid1));
  });

  it("tuple == tuple", () => {
    assertBoxedFalse(fun(tuple3, tuple3));
  });

  it("atom < atom", () => {
    assertBoxedTrue(fun(atomA, atomB));
  });

  it("float < atom (always)", () => {
    assertBoxedTrue(fun(float1, atomA));
  });

  it("float < float", () => {
    assertBoxedTrue(fun(float1, float2));
  });

  it("float < integer", () => {
    assertBoxedTrue(fun(float1, integer2));
  });

  it("integer < atom (always)", () => {
    assertBoxedTrue(fun(integer1, atomA));
  });

  it("integer < float", () => {
    assertBoxedTrue(fun(integer1, float2));
  });

  it("integer < integer", () => {
    assertBoxedTrue(fun(integer1, integer2));
  });

  it("pid < pid", () => {
    assertBoxedTrue(fun(pid1, pid2));
  });

  it("pid < tuple (always)", () => {
    assertBoxedTrue(fun(pid1, tuple3));
  });

  it("tuple < tuple", () => {
    assertBoxedTrue(fun(tuple2, tuple3));
  });

  it("atom > atom", () => {
    assertBoxedTrue(fun(atomB, atomA));
  });

  it("float > float", () => {
    assertBoxedTrue(fun(float2, float1));
  });

  it("float > integer", () => {
    assertBoxedTrue(fun(float2, integer1));
  });

  it("integer > float", () => {
    assertBoxedTrue(fun(integer2, float1));
  });

  it("integer > integer", () => {
    assertBoxedTrue(fun(integer2, integer1));
  });

  it("pid > pid", () => {
    assertBoxedTrue(fun(pid2, pid1));
  });

  it("tuple > tuple", () => {
    assertBoxedTrue(fun(tuple3, tuple2));
  });

  // TODO: reference, function, port, map, list, bitstring
});

describe("=:=/2", () => {
  const fun = Erlang["=:=/2"];

  it("atom == atom", () => {
    assertBoxedTrue(fun(atomA, atomA));
  });

  it("float == float", () => {
    assertBoxedTrue(fun(float1, float1));
  });

  it("float == integer", () => {
    assertBoxedFalse(fun(float1, integer1));
  });

  it("integer == float", () => {
    assertBoxedFalse(fun(integer1, float1));
  });

  it("integer == integer", () => {
    assertBoxedTrue(fun(integer1, integer1));
  });

  it("pid == pid", () => {
    assertBoxedTrue(fun(pid1, pid1));
  });

  it("tuple == tuple", () => {
    assertBoxedTrue(fun(tuple3, tuple3));
  });

  it("atom < atom", () => {
    assertBoxedFalse(fun(atomA, atomB));
  });

  it("float < atom (always)", () => {
    assertBoxedFalse(fun(float1, atomA));
  });

  it("float < float", () => {
    assertBoxedFalse(fun(float1, float2));
  });

  it("float < integer", () => {
    assertBoxedFalse(fun(float1, integer2));
  });

  it("integer < atom (always)", () => {
    assertBoxedFalse(fun(integer1, atomA));
  });

  it("integer < float", () => {
    assertBoxedFalse(fun(integer1, float2));
  });

  it("integer < integer", () => {
    assertBoxedFalse(fun(integer1, integer2));
  });

  it("pid < pid", () => {
    assertBoxedFalse(fun(pid1, pid2));
  });

  it("pid < tuple (always)", () => {
    assertBoxedFalse(fun(pid1, tuple3));
  });

  it("tuple < tuple", () => {
    assertBoxedFalse(fun(tuple2, tuple3));
  });

  it("atom > atom", () => {
    assertBoxedFalse(fun(atomB, atomA));
  });

  it("float > float", () => {
    assertBoxedFalse(fun(float2, float1));
  });

  it("float > integer", () => {
    assertBoxedFalse(fun(float2, integer1));
  });

  it("integer > float", () => {
    assertBoxedFalse(fun(integer2, float1));
  });

  it("integer > integer", () => {
    assertBoxedFalse(fun(integer2, integer1));
  });

  it("pid > pid", () => {
    assertBoxedFalse(fun(pid2, pid1));
  });

  it("tuple > tuple", () => {
    assertBoxedFalse(fun(tuple3, tuple2));
  });

  // TODO: reference, function, port, map, list, bitstring
});

describe("=</2", () => {
  const fun = Erlang["=</2"];

  it("atom == atom", () => {
    assertBoxedTrue(fun(atomA, atomA));
  });

  it("float == float", () => {
    assertBoxedTrue(fun(float1, float1));
  });

  it("float == integer", () => {
    assertBoxedTrue(fun(float1, integer1));
  });

  it("integer == float", () => {
    assertBoxedTrue(fun(integer1, float1));
  });

  it("integer == integer", () => {
    assertBoxedTrue(fun(integer1, integer1));
  });

  it("pid == pid", () => {
    assertBoxedTrue(fun(pid1, pid1));
  });

  it("tuple == tuple", () => {
    assertBoxedTrue(fun(tuple3, tuple3));
  });

  it("atom < atom", () => {
    assertBoxedTrue(fun(atomA, atomB));
  });

  it("float < atom (always)", () => {
    assertBoxedTrue(fun(float1, atomA));
  });

  it("float < float", () => {
    assertBoxedTrue(fun(float1, float2));
  });

  it("float < integer", () => {
    assertBoxedTrue(fun(float1, integer2));
  });

  it("integer < atom (always)", () => {
    assertBoxedTrue(fun(integer1, atomA));
  });

  it("integer < float", () => {
    assertBoxedTrue(fun(integer1, float2));
  });

  it("integer < integer", () => {
    assertBoxedTrue(fun(integer1, integer2));
  });

  it("pid < pid", () => {
    assertBoxedTrue(fun(pid1, pid2));
  });

  it("pid < tuple (always)", () => {
    assertBoxedTrue(fun(pid1, tuple3));
  });

  it("tuple < tuple", () => {
    assertBoxedTrue(fun(tuple2, tuple3));
  });

  it("atom > atom", () => {
    assertBoxedFalse(fun(atomB, atomA));
  });

  it("float > float", () => {
    assertBoxedFalse(fun(float2, float1));
  });

  it("float > integer", () => {
    assertBoxedFalse(fun(float2, integer1));
  });

  it("integer > float", () => {
    assertBoxedFalse(fun(integer2, float1));
  });

  it("integer > integer", () => {
    assertBoxedFalse(fun(integer2, integer1));
  });

  it("pid > pid", () => {
    assertBoxedFalse(fun(pid2, pid1));
  });

  it("tuple > tuple", () => {
    assertBoxedFalse(fun(tuple3, tuple2));
  });

  it("throws a not yet implemented error when the left argument type is not yet supported", () => {
    const expectedMessage =
      'Structural comparison currently supports only atoms, floats, integers, pids and tuples, got: "abc"';

    assert.throw(
      () => fun(Type.bitstring("abc"), integer1),
      HologramInterpreterError,
      expectedMessage,
    );
  });

  it("throws a not yet implemented error when the right argument type is not yet supported", () => {
    const expectedMessage =
      'Structural comparison currently supports only atoms, floats, integers, pids and tuples, got: "abc"';

    assert.throw(
      () => fun(integer1, Type.bitstring("abc")),
      HologramInterpreterError,
      expectedMessage,
    );
  });

  // TODO: reference, function, port, map, list, bitstring
});

describe("==/2", () => {
  const fun = Erlang["==/2"];

  it("atom == atom", () => {
    assertBoxedTrue(fun(atomA, atomA));
  });

  it("float == float", () => {
    assertBoxedTrue(fun(float1, float1));
  });

  it("float == integer", () => {
    assertBoxedTrue(fun(float1, integer1));
  });

  it("integer == float", () => {
    assertBoxedTrue(fun(integer1, float1));
  });

  it("integer == integer", () => {
    assertBoxedTrue(fun(integer1, integer1));
  });

  it("pid == pid", () => {
    assertBoxedTrue(fun(pid1, pid1));
  });

  it("tuple == tuple", () => {
    assertBoxedTrue(fun(tuple3, tuple3));
  });

  it("atom < atom", () => {
    assertBoxedFalse(fun(atomA, atomB));
  });

  it("float < atom (always)", () => {
    assertBoxedFalse(fun(float1, atomA));
  });

  it("float < float", () => {
    assertBoxedFalse(fun(float1, float2));
  });

  it("float < integer", () => {
    assertBoxedFalse(fun(float1, integer2));
  });

  it("integer < atom (always)", () => {
    assertBoxedFalse(fun(integer1, atomA));
  });

  it("integer < float", () => {
    assertBoxedFalse(fun(integer1, float2));
  });

  it("integer < integer", () => {
    assertBoxedFalse(fun(integer1, integer2));
  });

  it("pid < pid", () => {
    assertBoxedFalse(fun(pid1, pid2));
  });

  it("pid < tuple (always)", () => {
    assertBoxedFalse(fun(pid1, tuple3));
  });

  it("tuple < tuple", () => {
    assertBoxedFalse(fun(tuple2, tuple3));
  });

  it("atom > atom", () => {
    assertBoxedFalse(fun(atomB, atomA));
  });

  it("float > float", () => {
    assertBoxedFalse(fun(float2, float1));
  });

  it("float > integer", () => {
    assertBoxedFalse(fun(float2, integer1));
  });

  it("integer > float", () => {
    assertBoxedFalse(fun(integer2, float1));
  });

  it("integer > integer", () => {
    assertBoxedFalse(fun(integer2, integer1));
  });

  it("pid > pid", () => {
    assertBoxedFalse(fun(pid2, pid1));
  });

  it("tuple > tuple", () => {
    assertBoxedFalse(fun(tuple3, tuple2));
  });

  // TODO: reference, function, port, map, list, bitstring
});

describe(">/2", () => {
  const fun = Erlang[">/2"];

  it("atom == atom", () => {
    assertBoxedFalse(fun(atomA, atomA));
  });

  it("float == float", () => {
    assertBoxedFalse(fun(float1, float1));
  });

  it("float == integer", () => {
    assertBoxedFalse(fun(float1, integer1));
  });

  it("integer == float", () => {
    assertBoxedFalse(fun(integer1, float1));
  });

  it("integer == integer", () => {
    assertBoxedFalse(fun(integer1, integer1));
  });

  it("pid == pid", () => {
    assertBoxedFalse(fun(pid1, pid1));
  });

  it("tuple == tuple", () => {
    assertBoxedFalse(fun(tuple3, tuple3));
  });

  it("atom < atom", () => {
    assertBoxedFalse(fun(atomA, atomB));
  });

  it("float < atom (always)", () => {
    assertBoxedFalse(fun(float1, atomA));
  });

  it("float < float", () => {
    assertBoxedFalse(fun(float1, float2));
  });

  it("float < integer", () => {
    assertBoxedFalse(fun(float1, integer2));
  });

  it("integer < atom (always)", () => {
    assertBoxedFalse(fun(integer1, atomA));
  });

  it("integer < float", () => {
    assertBoxedFalse(fun(integer1, float2));
  });

  it("integer < integer", () => {
    assertBoxedFalse(fun(integer1, integer2));
  });

  it("pid < pid", () => {
    assertBoxedFalse(fun(pid1, pid2));
  });

  it("pid < tuple (always)", () => {
    assertBoxedFalse(fun(pid1, tuple3));
  });

  it("tuple < tuple", () => {
    assertBoxedFalse(fun(tuple2, tuple3));
  });

  it("atom > atom", () => {
    assertBoxedTrue(fun(atomB, atomA));
  });

  it("float > float", () => {
    assertBoxedTrue(fun(float2, float1));
  });

  it("float > integer", () => {
    assertBoxedTrue(fun(float2, integer1));
  });

  it("integer > float", () => {
    assertBoxedTrue(fun(integer2, float1));
  });

  it("integer > integer", () => {
    assertBoxedTrue(fun(integer2, integer1));
  });

  it("pid > pid", () => {
    assertBoxedTrue(fun(pid2, pid1));
  });

  it("tuple > tuple", () => {
    assertBoxedTrue(fun(tuple3, tuple2));
  });

  it("throws a not yet implemented error when the left argument type is not yet supported", () => {
    const expectedMessage =
      'Structural comparison currently supports only atoms, floats, integers, pids and tuples, got: "abc"';

    assert.throw(
      () => fun(Type.bitstring("abc"), integer1),
      HologramInterpreterError,
      expectedMessage,
    );
  });

  it("throws a not yet implemented error when the right argument type is not yet supported", () => {
    const expectedMessage =
      'Structural comparison currently supports only atoms, floats, integers, pids and tuples, got: "abc"';

    assert.throw(
      () => fun(integer1, Type.bitstring("abc")),
      HologramInterpreterError,
      expectedMessage,
    );
  });

  // TODO: reference, function, port, map, list, bitstring
});

describe(">=/2", () => {
  const fun = Erlang[">=/2"];

  it("atom == atom", () => {
    assertBoxedTrue(fun(atomA, atomA));
  });

  it("float == float", () => {
    assertBoxedTrue(fun(float1, float1));
  });

  it("float == integer", () => {
    assertBoxedTrue(fun(float1, integer1));
  });

  it("integer == float", () => {
    assertBoxedTrue(fun(integer1, float1));
  });

  it("integer == integer", () => {
    assertBoxedTrue(fun(integer1, integer1));
  });

  it("pid == pid", () => {
    assertBoxedTrue(fun(pid1, pid1));
  });

  it("tuple == tuple", () => {
    assertBoxedTrue(fun(tuple3, tuple3));
  });

  it("atom < atom", () => {
    assertBoxedFalse(fun(atomA, atomB));
  });

  it("float < atom (always)", () => {
    assertBoxedFalse(fun(float1, atomA));
  });

  it("float < float", () => {
    assertBoxedFalse(fun(float1, float2));
  });

  it("float < integer", () => {
    assertBoxedFalse(fun(float1, integer2));
  });

  it("integer < atom (always)", () => {
    assertBoxedFalse(fun(integer1, atomA));
  });

  it("integer < float", () => {
    assertBoxedFalse(fun(integer1, float2));
  });

  it("integer < integer", () => {
    assertBoxedFalse(fun(integer1, integer2));
  });

  it("pid < pid", () => {
    assertBoxedFalse(fun(pid1, pid2));
  });

  it("pid < tuple (always)", () => {
    assertBoxedFalse(fun(pid1, tuple3));
  });

  it("tuple < tuple", () => {
    assertBoxedFalse(fun(tuple2, tuple3));
  });

  it("atom > atom", () => {
    assertBoxedTrue(fun(atomB, atomA));
  });

  it("float > float", () => {
    assertBoxedTrue(fun(float2, float1));
  });

  it("float > integer", () => {
    assertBoxedTrue(fun(float2, integer1));
  });

  it("integer > float", () => {
    assertBoxedTrue(fun(integer2, float1));
  });

  it("integer > integer", () => {
    assertBoxedTrue(fun(integer2, integer1));
  });

  it("pid > pid", () => {
    assertBoxedTrue(fun(pid2, pid1));
  });

  it("tuple > tuple", () => {
    assertBoxedTrue(fun(tuple3, tuple2));
  });

  it("throws a not yet implemented error when the left argument type is not yet supported", () => {
    const expectedMessage =
      'Structural comparison currently supports only atoms, floats, integers, pids and tuples, got: "abc"';

    assert.throw(
      () => fun(Type.bitstring("abc"), integer1),
      HologramInterpreterError,
      expectedMessage,
    );
  });

  it("throws a not yet implemented error when the right argument type is not yet supported", () => {
    const expectedMessage =
      'Structural comparison currently supports only atoms, floats, integers, pids and tuples, got: "abc"';

    assert.throw(
      () => fun(integer1, Type.bitstring("abc")),
      HologramInterpreterError,
      expectedMessage,
    );
  });

  // TODO: reference, function, port, map, list, bitstring
});

describe("andalso/2", () => {
  it("returns false if the first argument is false", () => {
    const context = contextFixture({
      vars: {left: Type.boolean(false), right: Type.atom("abc")},
    });

    const result = Erlang["andalso/2"](
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

    const result = Erlang["andalso/2"](
      (context) => context.vars.left,
      (context) => context.vars.right,
      context,
    );

    assert.deepStrictEqual(result, Type.atom("abc"));
  });

  it("doesn't evaluate the second argument if the first argument is false", () => {
    const result = Erlang["andalso/2"](
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
        Erlang["andalso/2"](
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
  it("converts atom to (binary) bitstring", () => {
    const result = Erlang["atom_to_binary/1"](Type.atom("abc"));

    assert.deepStrictEqual(result, Type.bitstring("abc"));
  });

  it("raises ArgumentError if the argument is not an atom", () => {
    assertBoxedError(
      () => Erlang["atom_to_binary/1"](Type.integer(123)),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(1, "not an atom"),
    );
  });
});

describe("atom_to_list/1", () => {
  it("empty atom", () => {
    const result = Erlang["atom_to_list/1"](Type.atom(""));
    assert.deepStrictEqual(result, Type.list([]));
  });

  it("ASCII atom", () => {
    const result = Erlang["atom_to_list/1"](Type.atom("abc"));

    assert.deepStrictEqual(
      result,
      Type.list([Type.integer(97), Type.integer(98), Type.integer(99)]),
    );
  });

  it("Unicode atom", () => {
    const result = Erlang["atom_to_list/1"](Type.atom("全息图"));

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
      () => Erlang["atom_to_list/1"](Type.integer(123)),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(1, "not an atom"),
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
  const encoding = Type.atom("utf8");

  it("converts a binary bitstring to an already existing atom", () => {
    const binary = Type.bitstring("Elixir.Kernel");
    const result = Erlang["binary_to_atom/2"](binary, encoding);

    assert.deepStrictEqual(result, Type.alias("Kernel"));
  });

  it("converts a binary bitstring to a not existing yet atom", () => {
    const randomStr = `${Math.random()}`;
    const binary = Type.bitstring(randomStr);
    const result = Erlang["binary_to_atom/2"](binary, encoding);

    assert.deepStrictEqual(result, Type.atom(randomStr));
  });

  it("raises ArgumentError if the first argument is a non-binary bitstring", () => {
    assertBoxedError(
      () => Erlang["binary_to_atom/2"](Type.bitstring([1, 0, 1]), encoding),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(1, "not a binary"),
    );
  });

  it("raises ArgumentErorr if the first argument is not a bitstring", () => {
    assertBoxedError(
      () => Erlang["binary_to_atom/2"](Type.atom("abc"), encoding),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(1, "not a binary"),
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

describe("bit_size/1", () => {
  it("bitstring", () => {
    const myBitstring = Type.bitstring([
      Type.bitstringSegment(Type.integer(2), {
        type: "integer",
        size: Type.integer(7),
      }),
    ]);

    const result = Erlang["bit_size/1"](myBitstring);

    assert.deepStrictEqual(result, Type.integer(7));
  });

  it("not bitstring", () => {
    const myAtom = Type.atom("abc");

    assertBoxedError(
      () => Erlang["bit_size/1"](myAtom),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(1, "not a bitstring"),
    );
  });
});

describe("element/2", () => {
  const tuple = Type.tuple([Type.integer(5), Type.integer(6), Type.integer(7)]);

  it("returns the element at the one-based index in the tuple", () => {
    const result = Erlang["element/2"](Type.integer(2), tuple);
    assert.deepStrictEqual(result, Type.integer(6));
  });

  it("raises ArgumentError if the first argument is not an integer", () => {
    assertBoxedError(
      () => Erlang["element/2"](Type.atom("abc"), tuple),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(1, "not an integer"),
    );
  });

  it("raises ArgumentError if the second argument is not a tuple", () => {
    assertBoxedError(
      () => Erlang["element/2"](Type.integer(1), Type.atom("abc")),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(2, "not a tuple"),
    );
  });

  it("raises ArgumentError if the given index is greater than the number of elements in the tuple", () => {
    assertBoxedError(
      () => Erlang["element/2"](Type.integer(10), tuple),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(1, "out of range"),
    );
  });

  it("raises ArgumentError if the given index is smaller than 1", () => {
    assertBoxedError(
      () => Erlang["element/2"](Type.integer(0), tuple),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(1, "out of range"),
    );
  });
});

it("error/1", () => {
  const reason = Type.errorStruct("MyError", "my message");

  assertBoxedError(() => Erlang["error/1"](reason), "MyError", "my message");
});

it("error/2", () => {
  const reason = Type.errorStruct("MyError", "my message");
  const args = Type.list([Type.integer(1, Type.integer(2))]);

  assertBoxedError(
    () => Erlang["error/2"](reason, args),
    "MyError",
    "my message",
  );
});

describe("hd/1", () => {
  it("returns the first item in the list", () => {
    const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
    const result = Erlang["hd/1"](list);

    assert.deepStrictEqual(result, Type.integer(1));
  });

  it("raises ArgumentError if the argument is an empty list", () => {
    assertBoxedError(
      () => Erlang["hd/1"](Type.list([])),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(1, "not a nonempty list"),
    );
  });

  it("raises ArgumentError if the argument is not a list", () => {
    assertBoxedError(
      () => Erlang["hd/1"](Type.integer(123)),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(1, "not a nonempty list"),
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
  describe("positive integer", () => {
    it("base = 1", () => {
      assertBoxedError(
        () =>
          Erlang["integer_to_binary/2"](Type.integer(123123), Type.integer(1)),
        "ArgumentError",
        Interpreter.buildErrorsFoundMsg(
          2,
          "not an integer in the range 2 through 36",
        ),
      );
    });

    it("base = 2", () => {
      const result = Erlang["integer_to_binary/2"](
        Type.integer(123123),
        Type.integer(2),
      );

      const expected = Type.bitstring("11110000011110011");

      assert.deepStrictEqual(result, expected);
    });

    it("base = 16", () => {
      const result = Erlang["integer_to_binary/2"](
        Type.integer(123123),
        Type.integer(16),
      );

      const expected = Type.bitstring("1E0F3");

      assert.deepStrictEqual(result, expected);
    });

    it("base = 36", () => {
      const result = Erlang["integer_to_binary/2"](
        Type.integer(123123),
        Type.integer(36),
      );

      const expected = Type.bitstring("2N03");

      assert.deepStrictEqual(result, expected);
    });

    it("base = 37", () => {
      assertBoxedError(
        () =>
          Erlang["integer_to_binary/2"](Type.integer(123123), Type.integer(37)),
        "ArgumentError",
        Interpreter.buildErrorsFoundMsg(
          2,
          "not an integer in the range 2 through 36",
        ),
      );
    });
  });

  it("negative integer", () => {
    const result = Erlang["integer_to_binary/2"](
      Type.integer(-123123),
      Type.integer(16),
    );

    const expected = Type.bitstring("-1E0F3");

    assert.deepStrictEqual(result, expected);
  });

  it("1st argument (integer) is not an integer", () => {
    assertBoxedError(
      () => Erlang["integer_to_binary/2"](Type.atom("abc"), Type.integer(16)),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(1, "not an integer"),
    );
  });

  it("2nd argument (base) is not an integer", () => {
    assertBoxedError(
      () =>
        Erlang["integer_to_binary/2"](Type.integer(123123), Type.atom("abc")),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(
        2,
        "not an integer in the range 2 through 36",
      ),
    );
  });
});

describe("is_atom/1", () => {
  const fun = Erlang["is_atom/1"];

  it("atom", () => {
    assertBoxedTrue(fun(Type.atom("abc")));
  });

  it("non-atom", () => {
    assertBoxedFalse(fun(Type.integer(123)));
  });
});

describe("is_binary/1", () => {
  const fun = Erlang["is_binary/1"];

  it("binary bitsting", () => {
    assertBoxedTrue(fun(Type.bitstring("abc")));
  });

  it("non-binary bitstring", () => {
    assertBoxedFalse(fun(Type.bitstring([0, 1, 0])));
  });

  it("non-bitstring", () => {
    assertBoxedFalse(fun(Type.atom("abc")));
  });
});

describe("is_bitstring/1", () => {
  const fun = Erlang["is_bitstring/1"];

  it("bitstring", () => {
    assertBoxedTrue(fun(Type.bitstring([0, 1, 0])));
  });

  it("non-bitstring", () => {
    assertBoxedFalse(fun(Type.atom("abc")));
  });
});

describe("is_float/1", () => {
  const fun = Erlang["is_float/1"];

  it("float", () => {
    assertBoxedTrue(fun(Type.float(1.0)));
  });

  it("non-float", () => {
    assertBoxedFalse(fun(Type.atom("abc")));
  });
});

describe("is_function/1", () => {
  const fun = Erlang["is_function/1"];

  it("function", () => {
    const term = Type.anonymousFunction(
      "dummyArity",
      "dummyClauses",
      "dummyContext",
    );

    assertBoxedTrue(fun(term));
  });

  it("non-function", () => {
    assertBoxedFalse(fun(Type.atom("abc")));
  });
});

describe("is_function/2", () => {
  const fun = Erlang["is_function/2"];

  it("function with the given arity", () => {
    const term = Type.anonymousFunction(3, "dummyClauses", "dummyContext");

    assertBoxedTrue(fun(term, Type.integer(3)));
  });

  it("function with a different arity", () => {
    const term = Type.anonymousFunction(3, "dummyClauses", "dummyContext");

    assertBoxedFalse(fun(term, Type.integer(4)));
  });

  it("non-function", () => {
    assertBoxedFalse(fun(Type.atom("abc")));
  });
});

describe("is_integer/1", () => {
  const fun = Erlang["is_integer/1"];

  it("integer", () => {
    assertBoxedTrue(fun(Type.integer(1)));
  });

  it("non-integer", () => {
    assertBoxedFalse(fun(Type.atom("abc")));
  });
});

describe("is_list/1", () => {
  const fun = Erlang["is_list/1"];

  it("list", () => {
    const term = Type.list([Type.integer(1), Type.integer(2)]);
    assertBoxedTrue(fun(term));
  });

  it("non-list", () => {
    assertBoxedFalse(fun(Type.atom("abc")));
  });
});

describe("is_map/1", () => {
  const fun = Erlang["is_map/1"];

  it("map", () => {
    const term = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    assertBoxedTrue(fun(term));
  });

  it("non-map", () => {
    assertBoxedFalse(fun(Type.atom("abc")));
  });
});

describe("is_number/1", () => {
  const fun = Erlang["is_number/1"];

  it("float", () => {
    assertBoxedTrue(fun(Type.float(1.0)));
  });

  it("integer", () => {
    assertBoxedTrue(fun(Type.integer(1)));
  });

  it("non-number", () => {
    assertBoxedFalse(fun(Type.atom("abc")));
  });
});

describe("is_pid/1", () => {
  const fun = Erlang["is_pid/1"];

  it("pid", () => {
    assertBoxedTrue(fun(Type.pid("my_node@my_host", [0, 11, 222])));
  });

  it("non-pid", () => {
    assertBoxedFalse(fun(Type.atom("abc")));
  });
});

describe("is_port/1", () => {
  const fun = Erlang["is_port/1"];

  it("port", () => {
    assertBoxedTrue(fun(Type.port("0.11")));
  });

  it("non-port", () => {
    assertBoxedFalse(fun(Type.atom("abc")));
  });
});

describe("is_reference/1", () => {
  const fun = Erlang["is_reference/1"];

  it("reference", () => {
    assertBoxedTrue(fun(Type.reference("0.1.2.3")));
  });

  it("non-reference", () => {
    assertBoxedFalse(fun(Type.atom("abc")));
  });
});

describe("is_tuple/1", () => {
  const fun = Erlang["is_tuple/1"];

  it("tuple", () => {
    const term = Type.tuple([Type.integer(1), Type.integer(2)]);
    assertBoxedTrue(fun(term));
  });

  it("non-tuple", () => {
    assertBoxedFalse(fun(Type.atom("abc")));
  });
});

describe("length/1", () => {
  const fun = Erlang["length/1"];

  it("returns the number of items in the list", () => {
    const term = Type.list([Type.integer(1), Type.integer(2)]);
    assert.deepStrictEqual(fun(term), Type.integer(2));
  });

  it("raises ArgumentError if the argument is not a list", () => {
    assertBoxedError(
      () => fun(Type.atom("abc")),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(1, "not a list"),
    );
  });
});

describe("map_size/1", () => {
  const fun = Erlang["map_size/1"];

  it("returns the number of items in the map", () => {
    const term = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    assert.deepStrictEqual(fun(term), Type.integer(2));
  });

  it("raises BadMapError if the argument is not a map", () => {
    assertBoxedError(
      () => fun(Type.atom("abc")),
      "BadMapError",
      "expected a map, got: :abc",
    );
  });
});

describe("orelse/2", () => {
  it("returns true if the first argument is true", () => {
    const context = contextFixture({
      vars: {left: Type.boolean(true), right: Type.atom("abc")},
    });

    const result = Erlang["orelse/2"](
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

    const result = Erlang["orelse/2"](
      (context) => context.vars.left,
      (context) => context.vars.right,
      context,
    );

    assert.deepStrictEqual(result, Type.atom("abc"));
  });

  it("doesn't evaluate the second argument if the first argument is true", () => {
    const result = Erlang["orelse/2"](
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
        Erlang["orelse/2"](
          (context) => context.vars.left,
          (context) => context.vars.right,
          context,
        ),
      "ArgumentError",
      "argument error: nil",
    );
  });
});

describe("tl/1", () => {
  describe("proper list", () => {
    it("1 item", () => {
      const list = Type.list([Type.integer(1)]);
      const result = Erlang["tl/1"](list);
      const expected = Type.list([]);

      assert.deepStrictEqual(result, expected);
    });

    it("2 items", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = Erlang["tl/1"](list);
      const expected = Type.list([Type.integer(2)]);

      assert.deepStrictEqual(result, expected);
    });

    it("3 items", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const result = Erlang["tl/1"](list);
      const expected = Type.list([Type.integer(2), Type.integer(3)]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("improper list", () => {
    it("2 items", () => {
      const list = Type.improperList([Type.integer(1), Type.integer(2)]);
      const result = Erlang["tl/1"](list);
      const expected = Type.integer(2);

      assert.deepStrictEqual(result, expected);
    });

    it("3 items", () => {
      const list = Type.improperList([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const result = Erlang["tl/1"](list);
      const expected = Type.improperList([Type.integer(2), Type.integer(3)]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("errors", () => {
    it("raises ArgumentError if the argument is an empty boxed list", () => {
      assertBoxedError(
        () => Erlang["tl/1"](Type.list([])),
        "ArgumentError",
        Interpreter.buildErrorsFoundMsg(1, "not a nonempty list"),
      );
    });

    it("raises ArgumentError if the argument is not a boxed list", () => {
      assertBoxedError(
        () => Erlang["tl/1"](Type.integer(123)),
        "ArgumentError",
        Interpreter.buildErrorsFoundMsg(1, "not a nonempty list"),
      );
    });
  });
});

describe("tuple_to_list/1", () => {
  it("returns a list corresponding to the given tuple", () => {
    const data = [Type.integer(1), Type.integer(2), Type.integer(3)];
    const tuple = Type.tuple(data);

    const result = Erlang["tuple_to_list/1"](tuple);
    const expected = Type.list(data);

    assert.deepStrictEqual(result, expected);
  });

  it("raises ArgumentError if the argument is not a tuple", () => {
    assertBoxedError(
      () => Erlang["tuple_to_list/1"](Type.atom("abc")),
      "ArgumentError",
      Interpreter.buildErrorsFoundMsg(1, "not a tuple"),
    );
  });
});
