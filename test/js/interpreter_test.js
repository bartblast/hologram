"use strict";

import { assert, assertBoxedFalse, assertBoxedTrue, assertFrozen, cleanup } from "./support/commons";
beforeEach(() => cleanup())

import { HologramNotImplementedError } from "../../assets/js/hologram/errors";
import Interpreter from "../../assets/js/hologram/interpreter"
import Map from "../../assets/js/hologram/elixir/map"
import Type from "../../assets/js/hologram/type"

describe("$addition_operator()", () => {
  it("adds integer and integer", () => {
    const left = Type.integer(1);
    const right = Type.integer(2);

    const result = Interpreter.$addition_operator(left, right);
    const expected = Type.integer(3);

    assert.deepStrictEqual(result, expected);
  });

  it("adds integer and float", () => {
    const left = Type.integer(1);
    const right = Type.float(2.0);

    const result = Interpreter.$addition_operator(left, right);
    const expected = Type.float(3.0);

    assert.deepStrictEqual(result, expected);
  });

  it("adds float and integer", () => {
    const left = Type.float(1.0);
    const right = Type.integer(2);

    const result = Interpreter.$addition_operator(left, right);
    const expected = Type.float(3.0);

    assert.deepStrictEqual(result, expected);
  });

  it("adds float and float", () => {
    const left = Type.float(1.0);
    const right = Type.float(2.0);

    const result = Interpreter.$addition_operator(left, right);
    const expected = Type.float(3.0);

    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    const left = Type.integer(1);
    const right = Type.integer(2);
    const result = Interpreter.$addition_operator(left, right);

    assertFrozen(result);
  });
});

describe("$cons_operator()", () => {
  it("creates a list from a head and a tail", () => {
    const head = Type.integer(1)
    const tail = Type.list([Type.integer(2), Type.integer(3)])

    const result = Interpreter.$cons_operator(head, tail)
    const expected = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)])

    assert.deepStrictEqual(result, expected);
  })
})

describe("$division_operator()", () => {
  it("divides 2 numbers", () => {
    const left = Type.integer(1);
    const right = Type.float(2.0);

    const result = Interpreter.$division_operator(left, right);
    const expected = Type.float(0.5);

    assert.deepStrictEqual(result, expected);
  });
});

describe("$dot_operator()", () => {
  let left, right, value, result;

  beforeEach(() => {
    value = Type.integer(2)

    let elems = {}
    elems[Type.atomKey("a")] = Type.integer(1)
    elems[Type.atomKey("b")] = value

    left =  Type.map(elems)
    right = Type.atom("b")
    
    result = Interpreter.$dot_operator(left, right)
  })

  it("fetches boxed map value by boxed key", () => {
    assert.deepStrictEqual(result, value) 
  })

  it("returns frozen object", () => {
    assertFrozen(result)
  })
})

describe("$equal_to_operator()", () => {
  // non-number == non-number
  it("returns boxed true for a boxed non-number equal to another boxed non-number", () => {
    const value1 = Type.boolean(true);
    const value2 = Type.boolean(true);
    const result = Interpreter.$equal_to_operator(value1, value2);

    assertBoxedTrue(result);
  });

  // non-number != non-number
  it("returns boxed false for a boxed non-number not equal to another boxed non-number", () => {
    const value1 = Type.boolean(true);
    const value2 = Type.string("abc");
    const result = Interpreter.$equal_to_operator(value1, value2);

    assertBoxedFalse(result);
  });

  // integer == integer
  it("returns boxed true for a boxed integer equal to another boxed integer", () => {
    const value1 = Type.integer(1);
    const value2 = Type.integer(1);
    const result = Interpreter.$equal_to_operator(value1, value2);

    assertBoxedTrue(result);
  });

  // integer != integer
  it("returns boxed false for a boxed integer not equal to another boxed integer", () => {
    const value1 = Type.integer(1);
    const value2 = Type.integer(2);
    const result = Interpreter.$equal_to_operator(value1, value2);

    assertBoxedFalse(result);
  });

  // integer == float
  it("returns boxed true for a boxed integer equal to a boxed float", () => {
    const value1 = Type.integer(1);
    const value2 = Type.float(1.0);
    const result = Interpreter.$equal_to_operator(value1, value2);

    assertBoxedTrue(result);
  });

  // integer != float
  it("returns boxed false for a boxed integer not equal to a boxed float", () => {
    const value1 = Type.integer(1);
    const value2 = Type.float(2.0);
    const result = Interpreter.$equal_to_operator(value1, value2);

    assertBoxedFalse(result);
  });

  // integer != non-number
  it("returns boxed false when a boxed integer is compared to a boxed value of non-number type", () => {
    const value1 = Type.integer(1);
    const value2 = Type.string("1");
    const result = Interpreter.$equal_to_operator(value1, value2);

    assertBoxedFalse(result);
  });

  // float == float
  it("returns boxed true for a boxed float equal to another boxed float", () => {
    const value1 = Type.float(1.0);
    const value2 = Type.float(1.0);
    const result = Interpreter.$equal_to_operator(value1, value2);

    assertBoxedTrue(result);
  });

  // float != float
  it("returns boxed false for a boxed float not equal to another boxed float", () => {
    const value1 = Type.float(1.0);
    const value2 = Type.float(2.0);
    const result = Interpreter.$equal_to_operator(value1, value2);

    assertBoxedFalse(result);
  });

  // float == integer
  it("returns boxed true for a boxed float equal to a boxed integer", () => {
    const value1 = Type.float(1.0);
    const value2 = Type.integer(1);
    const result = Interpreter.$equal_to_operator(value1, value2);

    assertBoxedTrue(result);
  });

  // float != integer
  it("returns boxed false for a boxed float not equal to a boxed integer", () => {
    const value1 = Type.float(1.0);
    const value2 = Type.integer(2);
    const result = Interpreter.$equal_to_operator(value1, value2);

    assertBoxedFalse(result);
  });

  // float != non-number
  it("returns boxed false when a boxed float is compared to a boxed value of non-number type", () => {
    const value1 = Type.float(1.0);
    const value2 = Type.string("1.0");
    const result = Interpreter.$equal_to_operator(value1, value2);

    assertBoxedFalse(result);
  });

  it("returns frozen object", () => {
    const val = Type.integer(1);
    const result = Interpreter.$equal_to_operator(val, val);

    assertFrozen(result);
  });
});

describe("isConsOperatorPatternMatched()", () => {
  let head, tail, left;

  beforeEach(() => {
    head = Type.integer(1)
    tail = Type.list([Type.integer(2), Type.integer(3)])
    left = Type.consOperatorPattern(head, tail)
  })

  it("returns false if the right arg is not a boxed list", () => {
    const right = Type.integer(4)
    const result = Interpreter.isConsOperatorPatternMatched(left, right)

    assert.isFalse(result)
  })

  it("returns false if the right arg is an empty boxed list", () => {
    const right = Type.list([])
    const result = Interpreter.isConsOperatorPatternMatched(left, right)

    assert.isFalse(result)
  })

  it("returns false if heads don't match by value", () => {
    const right = Type.list([Type.integer(4), Type.integer(2), Type.integer(3)])
    const result = Interpreter.isConsOperatorPatternMatched(left, right)

    assert.isFalse(result)
  })

  it("returns false if tails don't match by value", () => {
    const right = Type.list([head, Type.integer(4), Type.integer(3)])
    const result = Interpreter.isConsOperatorPatternMatched(left, right)

    assert.isFalse(result)
  })

  it("returns true if heads and tails match by value", () => {
    const right = Type.list([head, Type.integer(2), Type.integer(3)])
    const result = Interpreter.isConsOperatorPatternMatched(left, right)

    assert.isTrue(result)
  })

  it("returns true if heads and tails match by variable pattern", () => {
    left = Type.consOperatorPattern(Type.placeholder(), Type.placeholder())

    const right = Type.list([head, Type.integer(2), Type.integer(3)])
    const result = Interpreter.isConsOperatorPatternMatched(left, right)

    assert.isTrue(result)
  })

  it("returns true if heads match by value and tails match by variable pattern", () => {
    left = Type.consOperatorPattern(head, Type.placeholder())

    const right = Type.list([head, Type.integer(2), Type.integer(3)])
    const result = Interpreter.isConsOperatorPatternMatched(left, right)

    assert.isTrue(result)
  })

  it("returns true if heads match by variable pattern and tails match by value", () => {
    tail = Type.list([Type.integer(2), Type.integer(3)])
    left = Type.consOperatorPattern(Type.placeholder(), tail)

    const right = Type.list([head, Type.integer(2), Type.integer(3)])
    const result = Interpreter.isConsOperatorPatternMatched(left, right)

    assert.isTrue(result)
  })
})

describe("$list_concatenation_operator()", () => {
  it("concatenates 2 lists", () => {
    const left = Type.list([Type.integer(1), Type.integer(2)]);
    const right = Type.list([Type.integer(3), Type.integer(4)]);

    const result = Interpreter.$list_concatenation_operator(left, right);

    const expected = Type.list([
      Type.integer(1),
      Type.integer(2),
      Type.integer(3),
      Type.integer(4),
    ]);

    assert.deepStrictEqual(result, expected);
  });
});

describe("$membership_operator()", () => {
  it("calls Enum.$member()", () => {
    const left = Type.integer(1)
    const right = Type.list([Type.integer(1), Type.integer(2)])
    const result = Interpreter.$membership_operator(left, right)

    assertBoxedTrue(result)
  })
})

describe("$multiplication_operator()", () => {
  it("multiplies integer and integer", () => {
    const left = Type.integer(2);
    const right = Type.integer(3);

    const result = Interpreter.$multiplication_operator(left, right);
    const expected = Type.integer(6);

    assert.deepStrictEqual(result, expected);
  });

  it("multiplies integer and float", () => {
    const left = Type.integer(2);
    const right = Type.float(3.0);

    const result = Interpreter.$multiplication_operator(left, right);
    const expected = Type.float(6.0);

    assert.deepStrictEqual(result, expected);
  });

  it("multiplies float and integer", () => {
    const left = Type.float(2.0);
    const right = Type.integer(3);

    const result = Interpreter.$multiplication_operator(left, right);
    const expected = Type.float(6.0);

    assert.deepStrictEqual(result, expected);
  });

  it("multiplies float and float", () => {
    const left = Type.float(2.0);
    const right = Type.float(3.0);

    const result = Interpreter.$multiplication_operator(left, right);
    const expected = Type.float(6.0);

    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    const left = Type.integer(1);
    const right = Type.integer(2);
    const result = Interpreter.$multiplication_operator(left, right);

    assertFrozen(result);
  });
});

describe("$not_equal_to_operator()", () => {
  it("returns boxed true if both args are not equal", () => {
    const left = Type.boolean(true);
    const right = Type.boolean(false);
    const result = Interpreter.$not_equal_to_operator(left, right);

    assertBoxedTrue(result);
  });

  it("returns boxed false if both args are equal", () => {
    const left = Type.boolean(true);
    const right = Type.boolean(true);
    const result = Interpreter.$not_equal_to_operator(left, right);

    assertBoxedFalse(result);
  });
})

describe("$relaxed_boolean_and_operator()", () => {
  it("returns the second arg if the first one is truthy", () => {
    const left = Type.integer(1);
    const right = Type.integer(2);
    const result = Interpreter.$relaxed_boolean_and_operator(left, right);

    assert.deepStrictEqual(result, right);
  });

  it("returns the first arg if it is falsy", () => {
    const left = Type.nil();
    const right = Type.integer(2);
    const result = Interpreter.$relaxed_boolean_and_operator(left, right);

    assert.deepStrictEqual(result, left);
  });
});

describe("$relaxed_boolean_not_operator()", () => {
  it("returns boxed true if the arg is boxed false", () => {
    const value = Type.boolean(false)
    const result = Interpreter.$relaxed_boolean_not_operator(value);

    assertBoxedTrue(result)
  })

  it("returns boxed true if the arg is boxed nil", () => {
    const value = Type.nil()
    const result = Interpreter.$relaxed_boolean_not_operator(value);

    assertBoxedTrue(result)
  })

  it("returns boxed false if the arg is boxed true", () => {
    const value = Type.boolean(true)
    const result = Interpreter.$relaxed_boolean_not_operator(value);

    assertBoxedFalse(result)
  })

  it("returns boxed false if the arg is of other data type", () => {
    const value = Type.integer(1)
    const result = Interpreter.$relaxed_boolean_not_operator(value);

    assertBoxedFalse(result)
  })
})

describe("$relaxed_boolean_or()", () => {
  it("returns the first arg if it is truthy", () => {
    const left = Type.integer(1);
    const right = Type.integer(2);
    const result = Interpreter.$relaxed_boolean_or_operator(left, right);

    assert.deepStrictEqual(result, left);
  });

  it("returns the second arg if the first is falsy", () => {
    const left = Type.nil();
    const right = Type.integer(2);
    const result = Interpreter.$relaxed_boolean_or_operator(left, right);

    assert.deepStrictEqual(result, right);
  });
});

describe("caseExpression()", () => {
  it("returns the result of the clauses anonymous function given", () => {
    const clausesAnonFun = function(param) {
      return param
    }

    const result = Interpreter.caseExpression(123, clausesAnonFun)
    assert.equal(result, 123)
  })

  it("returns frozen object", () => {
    const clausesAnonFun = function(param) {
      return param
    }

    const result = Interpreter.caseExpression({}, clausesAnonFun)
    assertFrozen(result)
  })
})

describe("isFunctionArgsPatternMatched()", () => {
  it("returns false if number of args is different than number of params", () => {
    const params = [Type.placeholder(), Type.placeholder()]
    const args = [Type.integer(1)]
    const result = Interpreter.isFunctionArgsPatternMatched(params, args)

    assert.isFalse(result)
  })

  it("returns false if at least one arg doesn't match the params pattern", () => {
    const params = [Type.placeholder(), Type.atom("a")]
    const args = [Type.atom("b"), Type.atom("c")]
    const result = Interpreter.isFunctionArgsPatternMatched(params, args)

    assert.isFalse(result)
  })

  it("returns true if the args match the params pattern", () => {
    const params = [Type.placeholder(), Type.atom("a")]
    const args = [Type.atom("b"), Type.atom("a")]
    const result = Interpreter.isFunctionArgsPatternMatched(params, args)

    assert.isTrue(result)
  })
})

describe("isMapPatternMatched()", () => {
  it("returns true if map boxed type left-hand side matches the map boxed type right-hand side", () => {
    let left = Type.map()
    left = Map.put(left, Type.atom("a"), Type.integer(1))

    let right = Type.map()
    right = Map.put(right, Type.atom("a"), Type.integer(1))
    right = Map.put(right, Type.atom("b"), Type.integer(2))

    const result = Interpreter.isPatternMatched(left, right)

    assert.isTrue(result)
  })

  it("returns false if right-hand side boxed map doesn't have a key from left-hand side boxed map", () => {
    let left = Type.map()
    left = Map.put(left, Type.atom("a"), Type.integer(1))
    left = Map.put(left, Type.atom("b"), Type.integer(2))
    
    let right = Type.map()
    right = Map.put(right, Type.atom("a"), Type.integer(1))

    const result = Interpreter.isPatternMatched(left, right)

    assert.isFalse(result)
  })

  it("returns false if value in left-hand side boxed map doesn't match the value in right-hand side boxed map", () => {
    let left = Type.map()
    left = Map.put(left, Type.atom("a"), Type.integer(1))
    left = Map.put(left, Type.atom("b"), Type.integer(2))
    
    let right = Type.map()
    right = Map.put(right, Type.atom("a"), Type.integer(1))
    right = Map.put(right, Type.atom("b"), Type.integer(3))

    const result = Interpreter.isPatternMatched(left, right)

    assert.isFalse(result)
  })
})

describe("isPatternMatched()", () => {
  it("returns true if the boxed type of the left-hand side is placeholder", () => {
    const left = Type.placeholder()
    const right = Type.integer(1)
    const result = Interpreter.isPatternMatched(left, right)

    assert.isTrue(result)
  })

  it("matches by cons operator pattern", () => {
    const left = Type.consOperatorPattern(Type.placeholder(), Type.placeholder())
    const right = Type.list([Type.integer(1), Type.integer(2)])
    const result = Interpreter.isPatternMatched(left, right)

    assert.isTrue(result)
  })

  it("returns false if the boxed type of the left-hand side is different than the boxed type of the right-hand side", () => {
    const left = Type.float(1.0)
    const right = Type.integer(1)
    const result = Interpreter.isPatternMatched(left, right)

    assert.isFalse(result)
  })

  it("returns true if atom boxed type left-hand side is equal to atom boxed type right-hand side", () => {
    const left = Type.atom("a")
    const right = Type.atom("a")
    const result = Interpreter.isPatternMatched(left, right)

    assert.isTrue(result)
  })

  it("returns false if atom boxed type left-hand side is not equal to atom boxed type right-hand side", () => {
    const left = Type.atom("a")
    const right = Type.atom("b")
    const result = Interpreter.isPatternMatched(left, right)

    assert.isFalse(result)
  })
  
  it("returns true if integer boxed type left-hand side is equal to integer boxed type right-hand side", () => {
    const left = Type.integer(1)
    const right = Type.integer(1)
    const result = Interpreter.isPatternMatched(left, right)

    assert.isTrue(result)
  })

  it("returns false if integer boxed type left-hand side is not equal to integer boxed type right-hand side", () => {
    const left = Type.integer(1)
    const right = Type.integer(2)
    const result = Interpreter.isPatternMatched(left, right)

    assert.isFalse(result)
  })

  it("throws an error for not implemented boxed types", () => {
    const left = {type: "not implemented", value: "a"}
    const right = {type: "not implemented", value: "b"}
    const expectedMessage = 'Interpreter.isPatternMatched(): left = {"type":"not implemented","value":"a"}'

    assert.throw(() => { Interpreter.isPatternMatched(left, right) }, HologramNotImplementedError, expectedMessage);
  })
})

describe("isEnumPatternMatched()", () => {
  it("returns true if list boxed type left-hand side matches the list boxed type right-hand side", () => {
    const left = Type.list([Type.integer(1), Type.integer(2)])
    const right = Type.list([Type.integer(1), Type.integer(2)])

    const result = Interpreter.isEnumPatternMatched(left, right)

    assert.isTrue(result)
  })

  it("returns false if left-hand side list item count is different than right-hand side list item count", () => {
    const left = Type.list([Type.integer(1), Type.integer(2)])
    const right = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)])

    const result = Interpreter.isEnumPatternMatched(left, right)

    assert.isFalse(result)
  })

  it("returns false if left-hand side list doesn't match right-hand side list", () => {
    const left = Type.list([Type.integer(1), Type.integer(2)])
    const right = Type.list([Type.integer(1), Type.integer(3)])

    const result = Interpreter.isEnumPatternMatched(left, right)

    assert.isFalse(result)
  })

  it("returns true if tuple boxed type left-hand side matches the tuple boxed type right-hand side", () => {
    const left = Type.tuple([Type.integer(1), Type.integer(2)])
    const right = Type.tuple([Type.integer(1), Type.integer(2)])

    const result = Interpreter.isEnumPatternMatched(left, right)

    assert.isTrue(result)
  })

  it("returns false if left-hand side tuple item count is different than right-hand side tuple item count", () => {
    const left = Type.tuple([Type.integer(1), Type.integer(2)])
    const right = Type.tuple([Type.integer(1), Type.integer(2), Type.integer(3)])

    const result = Interpreter.isEnumPatternMatched(left, right)

    assert.isFalse(result)
  })

  it("returns false if left-hand side tuple doesn't match right-hand side tuple", () => {
    const left = Type.tuple([Type.integer(1), Type.integer(2)])
    const right = Type.tuple([Type.integer(1), Type.integer(3)])

    const result = Interpreter.isEnumPatternMatched(left, right)

    assert.isFalse(result)
  })
})