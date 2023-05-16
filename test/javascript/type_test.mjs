"use strict";

import { assert, assertFrozen } from "../../assets/js/test_support.mjs";
import Type from "../../assets/js/type.mjs";

describe("atom()", () => {
  it("returns boxed atom value", () => {
    const result = Type.atom("test");
    const expected = { type: "atom", value: "test" };

    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    assertFrozen(Type.atom("test"));
  });
});

describe("float()", () => {
  it("returns boxed float value", () => {
    const result = Type.float(1.23);
    const expected = { type: "float", value: 1.23 };

    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    assertFrozen(Type.float(1.0));
  });
});

describe("integer()", () => {
  it("returns boxed integer value", () => {
    const result = Type.integer(1);
    const expected = { type: "integer", value: 1 };

    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    assertFrozen(Type.integer(1));
  });
});

describe("list()", () => {
  let data, expected, result;

  beforeEach(() => {
    data = [Type.integer(1), Type.integer(2)];

    result = Type.list(data);
    expected = { type: "list", data: data };
  });

  it("returns boxed list value", () => {
    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    assertFrozen(result);
  });
});
