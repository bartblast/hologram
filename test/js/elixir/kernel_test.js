import { assert } from "../support/commons"
import Kernel from "../../../assets/js/hologram/elixir/kernel";

describe("$add()", () => {
  it("adds integer and integer", () => {
    const arg1 = {type: "integer", value: 1}
    const arg2 = {type: "integer", value: 2}

    const result = Kernel.$add(arg1, arg2)
    const expected = {type: "integer", value: 3}

    assert.deepStrictEqual(result, expected) 
  })

  it("adds integer and float", () => {
    const arg1 = {type: "integer", value: 1}
    const arg2 = {type: "float", value: 2.0}

    const result = Kernel.$add(arg1, arg2)
    const expected = {type: "float", value: 3.0}

    assert.deepStrictEqual(result, expected) 
  })

  it("adds float and integer", () => {
    const arg1 = {type: "float", value: 1.0}
    const arg2 = {type: "integer", value: 2}

    const result = Kernel.$add(arg1, arg2)
    const expected = {type: "float", value: 3.0}

    assert.deepStrictEqual(result, expected) 
  })

  it("adds float and float", () => {
    const arg1 = {type: "float", value: 1.0}
    const arg2 = {type: "float", value: 2.0}

    const result = Kernel.$add(arg1, arg2)
    const expected = {type: "float", value: 3.0}

    assert.deepStrictEqual(result, expected) 
  })
})

describe("$dot()", () => {
  it("fetches map value by key", () => {
    const value = {type: "integer", value: 2}

    const map =  {
      type: "map", 
      data: {
        "~atom[a]": {type: "integer", value: 1},
        "~atom[b]": value
      }
    }

    const key = {type: "atom", value: "b"}
    const result = Kernel.$dot(map, key)

    assert.deepStrictEqual(result, value) 
    assert.notEqual(result, value)
  })
})

describe("to_string()", () => {
  it("converts a value to string type", () => {
    const value = {type: "integer", value: 1}

    const expected = {type: "string", value: "1"}
    const result = Kernel.to_string(value)

    assert.deepStrictEqual(result, expected)
  })
})