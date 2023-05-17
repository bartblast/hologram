"use strict";

import {
  assertBoxedTrue,
  assertBoxedFalse,
} from "../../../assets/js/test_support.mjs";

import erlang from "../../../assets/js/erlang/erlang.mjs";
import Type from "../../../assets/js/type.mjs";

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
