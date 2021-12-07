"use strict";

import {
  assert,
  assertBoxedFalse,
  assertBoxedTrue,
  assertFrozen,
  cleanup,
} from "../support/commons";
beforeEach(() => cleanup());

import { HologramNotImplementedError } from "../../../assets/js/hologram/errors";
import Kernel from "../../../assets/js/hologram/elixir/kernel";
import Map from "../../../assets/js/hologram/elixir/map";
import Type from "../../../assets/js/hologram/type";

describe("$add()", () => {
  it("adds integer and integer", () => {
    const arg1 = Type.integer(1);
    const arg2 = Type.integer(2);

    const result = Kernel.$add(arg1, arg2);
    const expected = Type.integer(3);

    assert.deepStrictEqual(result, expected);
  });

  it("adds integer and float", () => {
    const arg1 = Type.integer(1);
    const arg2 = Type.float(2.0);

    const result = Kernel.$add(arg1, arg2);
    const expected = Type.float(3.0);

    assert.deepStrictEqual(result, expected);
  });

  it("adds float and integer", () => {
    const arg1 = Type.float(1.0);
    const arg2 = Type.integer(2);

    const result = Kernel.$add(arg1, arg2);
    const expected = Type.float(3.0);

    assert.deepStrictEqual(result, expected);
  });

  it("adds float and float", () => {
    const arg1 = Type.float(1.0);
    const arg2 = Type.float(2.0);

    const result = Kernel.$add(arg1, arg2);
    const expected = Type.float(3.0);

    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    const arg1 = Type.integer(1);
    const arg2 = Type.integer(2);
    const result = Kernel.$add(arg1, arg2);

    assertFrozen(result);
  });
});

describe("apply()", () => {
  let functionName, module;

  beforeEach(() => {
    module = Type.module("ModuleStub1");
    functionName = Type.atom("test");
  });

  // apply/3
  it("invokes the function on the module with the args", () => {
    const args = Type.list([Type.integer(1), Type.integer(2)]);

    const result = Kernel.apply(module, functionName, args);
    const expected = Type.integer(3);

    assert.deepStrictEqual(result, expected);
  });

  // apply/2
  it("throws an error if number of args is different than 3", () => {
    const expectedMessage =
      'Kernel.apply(): arguments = {"0":{"type":"module","className":"ModuleStub1"},"1":{"type":"atom","value":"test"}}';
    assert.throw(
      () => {
        Kernel.apply(module, functionName);
      },
      HologramNotImplementedError,
      expectedMessage
    );
  });
});

describe("$boolean_and()", () => {
  it("returns the second arg if the first one is truthy", () => {
    const left = Type.integer(1)
    const right = Type.integer(2)
    const result = Kernel.$boolean_and(left, right)

    assert.deepStrictEqual(result, right)
  })

  it("returns the first arg if it is falsy", () => {
    const left = Type.nil()
    const right = Type.integer(2)
    const result = Kernel.$boolean_and(left, right)

    assert.deepStrictEqual(result, left)
  })
})

describe("$equal_to()", () => {
  // boolean == boolean
  it("returns boxed true for a boxed boolean equal to another boxed boolean", () => {
    const value1 = Type.boolean(true);
    const value2 = Type.boolean(true);
    const result = Kernel.$equal_to(value1, value2);

    assertBoxedTrue(result);
  });

  // boolean != boolean
  it("returns boxed false for a boxed boolean not equal to another boxed boolean", () => {
    const value1 = Type.boolean(true);
    const value2 = Type.boolean(false);
    const result = Kernel.$equal_to(value1, value2);

    assertBoxedFalse(result);
  });

  // boolean != non-boolean
  it("returns boxed false when a boxed boolean is compared to a boxed value of different type", () => {
    const value1 = Type.boolean(true);
    const value2 = Type.string("true");
    const result = Kernel.$equal_to(value1, value2);

    assertBoxedFalse(result);
  });

  // integer == integer
  it("returns boxed true for a boxed integer equal to another boxed integer", () => {
    const value1 = Type.integer(1);
    const value2 = Type.integer(1);
    const result = Kernel.$equal_to(value1, value2);

    assertBoxedTrue(result);
  });

  // integer != integer
  it("returns boxed false for a boxed integer not equal to another boxed integer", () => {
    const value1 = Type.integer(1);
    const value2 = Type.integer(2);
    const result = Kernel.$equal_to(value1, value2);

    assertBoxedFalse(result);
  });

  // integer == float
  it("returns boxed true for a boxed integer equal to a boxed float", () => {
    const value1 = Type.integer(1);
    const value2 = Type.float(1.0);
    const result = Kernel.$equal_to(value1, value2);

    assertBoxedTrue(result);
  });

  // integer != float
  it("returns boxed false for a boxed integer not equal to a boxed float", () => {
    const value1 = Type.integer(1);
    const value2 = Type.float(2.0);
    const result = Kernel.$equal_to(value1, value2);

    assertBoxedFalse(result);
  });

  // integer != non-number
  it("returns boxed false when a boxed integer is compared to a boxed value of non-number type", () => {
    const value1 = Type.integer(1);
    const value2 = Type.string("1");
    const result = Kernel.$equal_to(value1, value2);

    assertBoxedFalse(result);
  });

  // float == float
  it("returns boxed true for a boxed float equal to another boxed float", () => {
    const value1 = Type.float(1.0);
    const value2 = Type.float(1.0);
    const result = Kernel.$equal_to(value1, value2);

    assertBoxedTrue(result);
  });

  // float != float
  it("returns boxed false for a boxed float not equal to another boxed float", () => {
    const value1 = Type.float(1.0);
    const value2 = Type.float(2.0);
    const result = Kernel.$equal_to(value1, value2);

    assertBoxedFalse(result);
  });

  // float == integer
  it("returns boxed true for a boxed float equal to a boxed integer", () => {
    const value1 = Type.float(1.0);
    const value2 = Type.integer(1);
    const result = Kernel.$equal_to(value1, value2);

    assertBoxedTrue(result);
  });

  // float != integer
  it("returns boxed false for a boxed float not equal to a boxed integer", () => {
    const value1 = Type.float(1.0);
    const value2 = Type.integer(2);
    const result = Kernel.$equal_to(value1, value2);

    assertBoxedFalse(result);
  });

  // float != non-number
  it("returns boxed false when a boxed float is compared to a boxed value of non-number type", () => {
    const value1 = Type.float(1.0);
    const value2 = Type.string("1.0");
    const result = Kernel.$equal_to(value1, value2);

    assertBoxedFalse(result);
  });

  it("throws an error for not implemented types", () => {
    const val = { type: "not implemented", value: "test" };
    const expectedMessage =
      'Kernel.$equal_to(): boxedVal1 = {"type":"not implemented","value":"test"}';

    assert.throw(
      () => {
        Kernel.$equal_to(val, val);
      },
      HologramNotImplementedError,
      expectedMessage
    );
  });

  it("returns frozen object", () => {
    const val = Type.integer(1);
    const result = Kernel.$equal_to(val, val);

    assertFrozen(result);
  });
});

describe("if()", () => {
  it("returns doClause result if condition is truthy", () => {
    const expected = Type.integer(1);
    const condition = function () {
      return Type.boolean(true);
    };
    const doClause = function () {
      return expected;
    };
    const elseClause = function () {
      return Type.integer(2);
    };

    const result = Kernel.if(condition, doClause, elseClause);
    assert.equal(result, expected);
  });

  it("returns elseClause result if condition is not truthy", () => {
    const expected = Type.integer(2);
    const condition = function () {
      return Type.boolean(false);
    };
    const doClause = function () {
      return Type.integer(1);
    };
    const elseClause = function () {
      return expected;
    };

    const result = Kernel.if(condition, doClause, elseClause);
    assert.equal(result, expected);
  });

  it("returns frozen object", () => {
    const condition = function () {
      return Type.boolean(true);
    };
    const doClause = function () {
      return Type.integer(1);
    };
    const elseClause = function () {
      return Type.integer(2);
    };

    const result = Kernel.if(condition, doClause, elseClause);
    assertFrozen(result);
  });
});

describe("put_in()", () => {
  it("puts value nested 1 level deep", () => {
    let data = Type.map()
    data = Map.put(data, Type.atom("test_key"), Type.string("abc"))

    const keys = Type.list([Type.atom("test_key")])
    const result = Kernel.put_in(data, keys, Type.string("xyz"))

    let expected = Type.map()
    expected = Map.put(expected, Type.atom("test_key"), Type.string("xyz"))

    assert.deepStrictEqual(result, expected)
  })

  it("puts value nested more than 1 level deep", () => {
    let level2Data = Type.map()
    level2Data = Map.put(level2Data, Type.atom("test_key_2"), Type.string("abc"))

    let level1Data = Type.map()
    level1Data = Map.put(level1Data, Type.atom("test_key_1"), level2Data)

    const keys = Type.list([Type.atom("test_key_1"), Type.atom("test_key_2")])
    const result = Kernel.put_in(level1Data, keys, Type.string("xyz"))

    let expectedLevel2Data = Type.map()
    expectedLevel2Data = Map.put(expectedLevel2Data, Type.atom("test_key_2"), Type.string("xyz"))

    let expectedLevel1Data = Type.map()
    expectedLevel1Data = Map.put(expectedLevel1Data, Type.atom("test_key_1"), expectedLevel2Data)

    assert.deepStrictEqual(result, expectedLevel1Data)
  })
})

describe("to_string()", () => {
  it("converts boxed atom to boxed string", () => {
    const value = Type.atom("abc")

    const result = Kernel.to_string(value)
    const expected = Type.string("abc")

    assert.deepStrictEqual(result, expected)
  })

  it("converts boxed boolean to boxed string", () => {
    const value = Type.boolean(true)

    const result = Kernel.to_string(value)
    const expected = Type.string("true")

    assert.deepStrictEqual(result, expected)
  })

  it("converts boxed integer to boxed string", () => {
    const value = Type.integer(1)

    const result = Kernel.to_string(value)
    const expected = Type.string("1")

    assert.deepStrictEqual(result, expected)
  })

  it("returns the given arg if it is a boxed string", () => {
    const value = Type.string("abc")
    const result = Kernel.to_string(value)

    assert.deepStrictEqual(result, value)
  })

  it("converts boxed binary to boxed string", () => {
    const value = Type.binary([Type.string("abc"), Type.string("xyz")])

    const result = Kernel.to_string(value)
    const expected = Type.string("abcxyz")

    assert.deepStrictEqual(result, expected)
  })

  it("converts boxed nil to boxed string", () => {
    const value = Type.nil()

    const result = Kernel.to_string(value)
    const expected = Type.string("")

    assert.deepStrictEqual(result, expected)
  })

  it("throws an error for not implemented types", () => {
    const value = {type: "not implemented", value: "test"}
    const expectedMessage = 'Kernel.to_string(): boxedValue = {"type":"not implemented","value":"test"}'

    assert.throw(() => { Kernel.to_string(value) }, HologramNotImplementedError, expectedMessage);
  })
})
