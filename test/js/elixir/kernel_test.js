import { assert, assertBoxedFalse, assertBoxedTrue, assertFreezed } from "../support/commons"
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

  it("returns freezed object", () => {
    const arg1 = {type: "integer", value: 1}
    const arg2 = {type: "integer", value: 2}
    const result = Kernel.$add(arg1, arg2)
    
    assertFreezed(result)
  })
})

describe("$dot()", () => {
  let key, map, val, result;

  beforeEach(() => {
    val = {type: "integer", value: 2}

    map =  {
      type: "map", 
      data: {
        "~atom[a]": {type: "integer", value: 1},
        "~atom[b]": val
      }
    }

    key = {type: "atom", value: "b"}
    result = Kernel.$dot(map, key)
  })

  it("fetches boxed map value by boxed key", () => {
    assert.deepStrictEqual(result, val) 
  })

  it("returns freezed object", () => {
    assertFreezed(result)
  })
})

describe("$equal_to()", () => {
  // boolean == boolean
  it("returns boxed true for a boxed boolean equal to another boxed boolean", () => {
    const value1 = {type: "boolean", value: true}
    const value2 = {type: "boolean", value: true}

    const result = Kernel.$equal_to(value1, value2)
    assertBoxedTrue(result)
  })

  // boolean != boolean
  it("returns boxed false for a boxed boolean not equal to another boxed boolean", () => {
    const value1 = {type: "boolean", value: true}
    const value2 = {type: "boolean", value: false}

    const result = Kernel.$equal_to(value1, value2)
    assertBoxedFalse(result)
  })

  // boolean != non-boolean
  it("returns boxed false when a boxed boolean is compared to a boxed value of different type", () => {
    const value1 = {type: "boolean", value: true}
    const value2 = {type: "string", value: "true"}

    const result = Kernel.$equal_to(value1, value2)
    assertBoxedFalse(result)
  })

  // integer == integer
  it("returns boxed true for a boxed integer equal to another boxed integer", () => {
    const value1 = {type: "integer", value: 1}
    const value2 = {type: "integer", value: 1}
    
    const result = Kernel.$equal_to(value1, value2)
    assertBoxedTrue(result)
  })

  // integer != integer
  it("returns boxed false for a boxed integer not equal to another boxed integer", () => {
    const value1 = {type: "integer", value: 1}
    const value2 = {type: "integer", value: 2}

    const result = Kernel.$equal_to(value1, value2)
    assertBoxedFalse(result)
  })

  // integer == float
  it("returns boxed true for a boxed integer equal to a boxed float", () => {
    const value1 = {type: "integer", value: 1}
    const value2 = {type: "float", value: 1.0}

    const result = Kernel.$equal_to(value1, value2)
    assertBoxedTrue(result)
  })

  // integer != float
  it("returns boxed false for a boxed integer not equal to a boxed float", () => {
    const value1 = {type: "integer", value: 1}
    const value2 = {type: "float", value: 2.0}

    const result = Kernel.$equal_to(value1, value2)
    assertBoxedFalse(result)
  })

  // integer != non-number
  it("returns boxed false when a boxed integer is compared to a boxed value of non-number type", () => {
    const value1 = {type: "integer", value: 1}
    const value2 = {type: "string", value: "1"}

    const result = Kernel.$equal_to(value1, value2)
    assertBoxedFalse(result)
  })

  // float == float
  it("returns boxed true for a boxed float equal to another boxed float", () => {
    const value1 = {type: "float", value: 1.0}
    const value2 = {type: "float", value: 1.0}

    const result = Kernel.$equal_to(value1, value2)
    assertBoxedTrue(result)
  })

  // float != float
  it("returns boxed false for a boxed float not equal to another boxed float", () => {
    const value1 = {type: "float", value: 1.0}
    const value2 = {type: "float", value: 2.0}

    const result = Kernel.$equal_to(value1, value2)
    assertBoxedFalse(result)
  })

  // float == integer
  it("returns boxed true for a boxed float equal to a boxed integer", () => {
    const value1 = {type: "float", value: 1.0}
    const value2 = {type: "integer", value: 1}

    const result = Kernel.$equal_to(value1, value2)
    assertBoxedTrue(result)
  })

  // float != integer
  it("returns boxed false for a boxed float not equal to a boxed integer", () => {
    const value1 = {type: "float", value: 1.0}
    const value2 = {type: "integer", value: 2}

    const result = Kernel.$equal_to(value1, value2)
    assertBoxedFalse(result)
  })

  // float != non-number
  it("returns boxed false when a boxed float is compared to a boxed value of non-number type", () => {
    const value1 = {type: "float", value: 1.0}
    const value2 = {type: "string", value: "1.0"}

    const result = Kernel.$equal_to(value1, value2)
    assertBoxedFalse(result)
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