"use strict";

import { assert, cleanup } from "../support/commons";
beforeEach(() => cleanup());

import List from "../../../assets/js/hologram/elixir/list";
import Type from "../../../assets/js/hologram/type";

describe("insert_at()", () => {
  let list;

  beforeEach(() => {
    list = Type.list([Type.integer(1), Type.integer(2)]);
  });

  it("inserts at the beginning of the list", () => {
    const result = List.insert_at(list, 0, Type.integer(3))
    const expected = Type.list([Type.integer(3), Type.integer(1), Type.integer(2)])

    assert.deepStrictEqual(result, expected);
  })

  it("inserts in the middle of the list", () => {
    const result = List.insert_at(list, 1, Type.integer(3))
    const expected = Type.list([Type.integer(1), Type.integer(3), Type.integer(2)])

    assert.deepStrictEqual(result, expected);
  })

  it("inserts at the end of the list when index is equal to the lenght of the list", () => {
    const result = List.insert_at(list, 2, Type.integer(3))
    const expected = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)])

    assert.deepStrictEqual(result, expected);
  })

  it("inserts at the end of the list when index is set to -1", () => {
    const result = List.insert_at(list, -1, Type.integer(3))
    const expected = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)])

    assert.deepStrictEqual(result, expected);
  })

  it("caps the index at the list end", () => {
    const result = List.insert_at(list, 5, Type.integer(3))
    const expected = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)])

    assert.deepStrictEqual(result, expected);
  })

  it("works with negative indices", () => {
    const result = List.insert_at(list, -2, Type.integer(3))
    const expected = Type.list([Type.integer(1),  Type.integer(3), Type.integer(2)])

    assert.deepStrictEqual(result, expected);
  })
})