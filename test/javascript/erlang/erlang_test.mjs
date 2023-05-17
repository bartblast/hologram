"use strict";

import {
  assert,
  assertBoxedTrue,
  assertBoxedFalse,
} from "../../../assets/js/test_support.mjs";
import erlang from "../../../assets/js/erlang/erlang.mjs";
import Type from "../../../assets/js/type.mjs";

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
