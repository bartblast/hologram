"use strict";

import {
  assert,
  assertBoxedTrue,
  assertBoxedFalse,
} from "../../../assets/js/test_support.mjs";

import erlang from "../../../assets/js/erlang/erlang.mjs";
import Type from "../../../assets/js/type.mjs";

describe("$61$58$61/2 (=:=)", () => {
  it("returns boxed true if the args are of the same boxed primitive type and have equal values", () => {
    const result = erlang.$61$58$61(Type.integer(1), Type.integer(1));
    assertBoxedTrue(result);
  });

  it("returns boxed false if the args are not of the same boxed primitive type but have equal values", () => {
    const result = erlang.$61$58$61(Type.integer(1), Type.float(1.0));
    assertBoxedFalse(result);
  });

  it("returns boxed true if the left boxed arg of a composite type is deeply equal to the right boxed arg of a composite type", () => {
    const left = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.map([[Type.atom("c"), Type.integer(3)]])],
    ]);

    const right = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.map([[Type.atom("c"), Type.integer(3)]])],
    ]);

    const result = erlang.$61$58$61(left, right);

    assertBoxedTrue(result);
  });

  it("returns false if the left boxed arg of a composite type is not deeply equal to the right boxed arg of a composite type", () => {
    const left = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.map([[Type.atom("c"), Type.integer(3)]])],
    ]);

    const right = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.map([[Type.atom("c"), Type.integer(4)]])],
    ]);

    const result = Interpreter.isStrictlyEqual(left, right);

    assert.isFalse(result);
  });
});

describe("is_atom/1", () => {
  it("returns boxed true for boxed atoms", () => {
    const result = erlang.is_atom(Type.atom("abc"));
    assertBoxedTrue(result);
  });

  it("returns boxed false for types other than boxed atom", () => {
    const result = erlang.is_atom(Type.integer(123));
    assertBoxedFalse(result);
  });
});

describe("is_float/1", () => {
  it("returns boxed true for boxed floats", () => {
    const result = erlang.is_float(Type.float(1.23));
    assertBoxedTrue(result);
  });

  it("returns boxed false for types other than boxed float", () => {
    const result = erlang.is_float(Type.atom("abc"));
    assertBoxedFalse(result);
  });
});

describe("is_integer/1", () => {
  it("returns boxed true for boxed integers", () => {
    const result = erlang.is_integer(Type.integer(123));
    assertBoxedTrue(result);
  });

  it("returns boxed false for types other than boxed integer", () => {
    const result = erlang.is_integer(Type.atom("abc"));
    assertBoxedFalse(result);
  });
});

describe("is_number/1", () => {
  it("returns boxed true for boxed floats", () => {
    const result = erlang.is_number(Type.float(1.23));
    assertBoxedTrue(result);
  });

  it("returns boxed true for boxed integers", () => {
    const result = erlang.is_number(Type.integer(123));
    assertBoxedTrue(result);
  });

  it("returns boxed false for types other than boxed float or boxed integer", () => {
    const result = erlang.is_number(Type.atom("abc"));
    assertBoxedFalse(result);
  });
});

describe("length/1", () => {
  it("returns the number of items in a list", () => {
    const list = Type.list([Type.integer(1), Type.integer(2)]);
    const result = erlang.length(list);
    const expected = Type.integer(2);

    assert.deepStrictEqual(result, expected);
  });
});
