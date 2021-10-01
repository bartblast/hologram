import { assert, assertFreezed } from "./support/commons";
import Type from "../../assets/js/hologram/type";

describe("atom()", () => {
  it("returns boxed atom value", () => {
    const expected = {type: "atom", value: "test"}
    const result = Type.atom("test")
    assert.deepStrictEqual(result, expected)
  })

  it("returns freezed object", () => {
    const result = Type.atom("test")
    assertFreezed(result)
  })
})

describe("boolean()", () => {
  it("returns boxed boolean value", () => {
    const expected = {type: "boolean", value: true}
    const result = Type.boolean(true)
    assert.deepStrictEqual(result, expected)
  })

  it("returns freezed object", () => {
    const result = Type.boolean(true)
    assertFreezed(result)
  })
})

describe("integer()", () => {
  it("returns boxed integer value", () => {
    const expected = {type: "integer", value: 1}
    const result = Type.integer(1)
    assert.deepStrictEqual(result, expected)
  })

  it("returns freezed object", () => {
    const result = Type.integer(1)
    assertFreezed(result)
  })
})

describe("list()", () => {
  it("returns boxed list value", () => {
    const elems = [Type.integer(1), Type.integer(2)]
    const expected = {type: "list", data: elems}
    const result = Type.list(elems)
  
    assert.deepStrictEqual(result, expected)
  })

  it("returns freezed object", () => {
    const result = Type.list([[Type.integer(1), Type.integer(2)]])
    assertFreezed(result)
  })
})

describe("module()", () => {
  it("returns boxed module value", () => {
    const expected = {type: "module", class_name: "Elixir_ClassStub"}
    const result = Type.module("Elixir_ClassStub")
    assert.deepStrictEqual(result, expected)
  })


  it("returns freezed object", () => {
    const result = Type.module("Elixir_ClassStub")
    assertFreezed(result)
  })
})
