import { assert } from "../support/commons"
import Kernel from "../../../assets/js/hologram/elixir/kernel";
import Type from "../../../assets/js/hologram/type";

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

describe("$equal_to()", () => {
  it("boolean == boolean", () => {
    const value1 = {type: "boolean", value: true}
    const value2 = {type: "boolean", value: true}

    const result = Kernel.$equal_to(value1, value2)
    const expected = {type: "boolean", value: true}

    assert.deepStrictEqual(result, expected)
  })

  it("boolean != boolean", () => {
    const value1 = {type: "boolean", value: true}
    const value2 = {type: "boolean", value: false}

    const result = Kernel.$equal_to(value1, value2)
    const expected = {type: "boolean", value: false}

    assert.deepStrictEqual(result, expected)
  })

  it("boolean != non-boolean", () => {
    const value1 = {type: "boolean", value: true}
    const value2 = {type: "string", value: "true"}

    const result = Kernel.$equal_to(value1, value2)
    const expected = {type: "boolean", value: false}

    assert.deepStrictEqual(result, expected)
  })

  it("integer == integer", () => {
    const value1 = {type: "integer", value: 1}
    const value2 = {type: "integer", value: 1}

    const result = Kernel.$equal_to(value1, value2)
    const expected = {type: "boolean", value: true}

    assert.deepStrictEqual(result, expected)
  })

  it("integer != integer", () => {
    const value1 = {type: "integer", value: 1}
    const value2 = {type: "integer", value: 2}

    const result = Kernel.$equal_to(value1, value2)
    const expected = {type: "boolean", value: false}

    assert.deepStrictEqual(result, expected)
  })

  it("integer == float", () => {
    const value1 = {type: "integer", value: 1}
    const value2 = {type: "float", value: 1.0}

    const result = Kernel.$equal_to(value1, value2)
    const expected = {type: "boolean", value: true}

    assert.deepStrictEqual(result, expected)
  })

  it("integer != float", () => {
    const value1 = {type: "float", value: 1}
    const value2 = {type: "float", value: 2.0}

    const result = Kernel.$equal_to(value1, value2)
    const expected = {type: "boolean", value: false}

    assert.deepStrictEqual(result, expected)
  })

  it("integer != non-number", () => {
    const value1 = {type: "integer", value: 1}
    const value2 = {type: "string", value: "1"}

    const result = Kernel.$equal_to(value1, value2)
    const expected = {type: "boolean", value: false}

    assert.deepStrictEqual(result, expected)
  })

  it("float == float", () => {
    const value1 = {type: "float", value: 1.0}
    const value2 = {type: "float", value: 1.0}

    const result = Kernel.$equal_to(value1, value2)
    const expected = {type: "boolean", value: true}

    assert.deepStrictEqual(result, expected)
  })

  it("float != float", () => {
    const value1 = {type: "float", value: 1.0}
    const value2 = {type: "float", value: 2.0}

    const result = Kernel.$equal_to(value1, value2)
    const expected = {type: "boolean", value: false}

    assert.deepStrictEqual(result, expected)
  })

  it("float == integer", () => {
    const value1 = {type: "float", value: 1.0}
    const value2 = {type: "integer", value: 1}

    const result = Kernel.$equal_to(value1, value2)
    const expected = {type: "boolean", value: true}

    assert.deepStrictEqual(result, expected)
  })

  it("float != integer", () => {
    const value1 = {type: "float", value: 1.0}
    const value2 = {type: "integer", value: 2}

    const result = Kernel.$equal_to(value1, value2)
    const expected = {type: "boolean", value: false}

    assert.deepStrictEqual(result, expected)
  })

  it("float != non-number", () => {
    const value1 = {type: "float", value: 1.0}
    const value2 = {type: "string", value: "1"}

    const result = Kernel.$equal_to(value1, value2)
    const expected = {type: "boolean", value: false}

    assert.deepStrictEqual(result, expected)
  })
})

describe("apply()", () => {
  it("apply/3", () => {
    const module = Type.module("ModuleStub1")
    const function_name = Type.atom("test")
    const args = Type.list([Type.integer(1), Type.integer(2)])

    const result = Kernel.apply(module, function_name, args)
    const expected = Type.integer(3)

    assert.deepStrictEqual(result, expected) 
  })
})

describe("if()", () => {
  it("condition is truthy", () => {
    const expected = {type: "integer", value: 1}
    const condition = (function() { return {type: "boolean", value: true} })
    const doClause = (function() { return expected })
    const elseClause = (function() { return {type: "integer", value: 2} })
    
    const result = Kernel.if(condition, doClause, elseClause)
    assert.equal(result, expected) 
  })

  it("condition is not truthy", () => {
    const expected = {type: "integer", value: 2}
    const condition = (function() { return {type: "boolean", value: false} })
    const doClause = (function() { return {type: "integer", value: 1} })
    const elseClause = (function() { return expected })
    
    const result = Kernel.if(condition, doClause, elseClause)
    assert.equal(result, expected) 
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