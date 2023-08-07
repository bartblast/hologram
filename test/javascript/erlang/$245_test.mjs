// function: :erlang.-/2

"use strict";

import $245 from "../../../assets/js/erlang/$245.mjs";
import Type from "../../../assets/js/type.mjs";

import {
  assert,
  linkModules,
  unlinkModules,
} from "../../../assets/js/test_support.mjs";

before(() => linkModules());
after(() => unlinkModules());

describe("$245()", () => {
  it("subtracts integer and integer", () => {
    const left = Type.integer(3);
    const right = Type.integer(1);

    const result = $245(left, right);
    const expected = Type.integer(2);

    assert.deepStrictEqual(result, expected);
  });

  it("subtracts integer and float", () => {
    const left = Type.integer(3);
    const right = Type.float(1.0);

    const result = $245(left, right);
    const expected = Type.float(2.0);

    assert.deepStrictEqual(result, expected);
  });

  it("subtracts float and integer", () => {
    const left = Type.float(3.0);
    const right = Type.integer(1);

    const result = $245(left, right);
    const expected = Type.float(2.0);

    assert.deepStrictEqual(result, expected);
  });

  it("subtracts float and float", () => {
    const left = Type.float(3.0);
    const right = Type.float(1.0);

    const result = $245(left, right);
    const expected = Type.float(2.0);

    assert.deepStrictEqual(result, expected);
  });
});
