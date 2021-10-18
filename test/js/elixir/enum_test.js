"use strict";

import { assert, assertBoxedFalse, assertBoxedTrue } from "../support/commons";

import Enum from "../../../assets/js/hologram/elixir/enum";
import { HologramNotImplementedError } from "../../../assets/js/hologram/errors";
import Type from "../../../assets/js/hologram/type";

describe("member$question()", () => {
  let list;

  beforeEach(() => {
    const elems = [Type.integer(1), Type.integer(2)];
    list = Type.list(elems);
  });

  it("returns boxed true boolean value if the list contains the element", () => {
    const elem = Type.integer(2);
    const result = Enum.member$question(list, elem);

    assertBoxedTrue(result);
  });

  it("returns boxed false boolean value if the list doesn't contain the element", () => {
    const elem = Type.integer(3);
    const result = Enum.member$question(list, elem);

    assertBoxedFalse(result);
  });

  it("uses strictly equal to operator", () => {
    const elems = [Type.float(1.0), Type.float(2.0), Type.float(3.0)];
    const list = Type.list(elems);

    const result1 = Enum.member$question(list, Type.integer(2));
    assertBoxedFalse(result1);

    const result2 = Enum.member$question(list, Type.float(2.0));
    assertBoxedTrue(result2);
  });

  it("throws an error for not implemented enumerable types", () => {
    const enumerable = { type: "not implemented", value: "test" };
    const elem = Type.integer(1);
    const expectedMessage =
      'Enum.member$question(): enumerable = {"type":"not implemented","value":"test"}, elem = {"type":"integer","value":1}';

    assert.throw(
      () => {
        Enum.member$question(enumerable, elem);
      },
      HologramNotImplementedError,
      expectedMessage
    );
  });
});
