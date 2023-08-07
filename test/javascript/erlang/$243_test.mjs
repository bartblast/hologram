// :erlang.+/2

"use strict";

import $243 from "../../../assets/js/erlang/$243.mjs";
import Type from "../../../assets/js/type.mjs";

import {
  assert,
  linkModules,
  unlinkModules,
} from "../../../assets/js/test_support.mjs";

before(() => linkModules());
after(() => unlinkModules());

describe("$243()", () => {
  it("adds integer and integer", () => {
    const left = Type.integer(1);
    const right = Type.integer(2);

    const result = $243(left, right);
    const expected = Type.integer(3);

    assert.deepStrictEqual(result, expected);
  });

  it("adds integer and float", () => {
    const left = Type.integer(1);
    const right = Type.float(2.0);

    const result = $243(left, right);
    const expected = Type.float(3.0);

    assert.deepStrictEqual(result, expected);
  });

  it("adds float and integer", () => {
    const left = Type.float(1.0);
    const right = Type.integer(2);

    const result = $243(left, right);
    const expected = Type.float(3.0);

    assert.deepStrictEqual(result, expected);
  });

  it("adds float and float", () => {
    const left = Type.float(1.0);
    const right = Type.float(2.0);

    const result = $243(left, right);
    const expected = Type.float(3.0);

    assert.deepStrictEqual(result, expected);
  });
});
