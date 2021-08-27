import { assert } from "./support/commons";
import Type from "../../assets/js/hologram/type";

describe("boolean()", () => {
  it("returns boxed boolean value", () => {
    const expected = {type: "boolean", value: true}
    const result = Type.boolean(true)
    assert.deepStrictEqual(result, expected)
  })
})

describe("integer()", () => {
  it("returns boxed integer value", () => {
    const expected = {type: "integer", value: 1}
    const result = Type.integer(1)
    assert.deepStrictEqual(result, expected)
  })
})

describe("module()", () => {
  it("returns boxed module value", () => {
    const expected = {type: "module", class_name: "Elixir_ClassStub"}
    const result = Type.module("Elixir_ClassStub")
    assert.deepStrictEqual(result, expected)
  })
})
