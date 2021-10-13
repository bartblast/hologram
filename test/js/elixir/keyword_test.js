"use strict";

import { assert, assertBoxedFalse, assertBoxedTrue } from "../support/commons"
import Keyword from "../../../assets/js/hologram/elixir/keyword";
import Type from "../../../assets/js/hologram/type";

describe("delete()", () => {
  const key = Type.atom("a")

  const expected = Type.list([
    Type.tuple([Type.atom("b"), Type.integer(2)])
  ])

  it("deletes the entry in the keyword list for specific a key when there is one matching entry", () => {
    const keywords = Type.list([
      Type.tuple([key, Type.integer(1)]),
      Type.tuple([Type.atom("b"), Type.integer(2)])
    ])

    const result = Keyword.delete(keywords, key)

    assert.deepStrictEqual(result, expected)
  })

  it("deletes the entries in the keyword list for specific a key when there are multiple matching entries", () => {
    const keywords = Type.list([
      Type.tuple([key, Type.integer(1)]),
      Type.tuple([Type.atom("b"), Type.integer(2)]),
      Type.tuple([key, Type.integer(3)])
    ])

    const result = Keyword.delete(keywords, key)

    assert.deepStrictEqual(result, expected)
  })

  it("returns the keyword list unchanged if there are no entries matching the given key", () => {
    const result = Keyword.delete(expected, key)
    assert.deepStrictEqual(result, expected)
  })
})

describe("has_key$question()", () => {
  let keywords;

  beforeEach(() => {
    keywords = Type.list([
      Type.tuple([Type.atom("a"), Type.integer(1)]),
      Type.tuple([Type.atom("b"), Type.integer(2)])
    ])
  })
  
  it("returns boxed true if the keyword list has the key", () => {
    const key = Type.atom("b")
    const result = Keyword.has_key$question(keywords, key)

    assertBoxedTrue(result)
  })

  it("returns boxed false if the keyword list doesn't have the key", () => {
    const key = Type.atom("c")
    const result = Keyword.has_key$question(keywords, key)

    assertBoxedFalse(result)
  })
})