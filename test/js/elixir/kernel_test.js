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

describe("elem()", () => {
  it("gets the element at the zero-based index in tuple", () => {
    const tuple = Type.tuple([
      Type.integer(1),
      Type.integer(2),
      Type.integer(3),
    ]);
    const index = 1;

    const result = Kernel.elem(tuple, index);
    const expected = Type.integer(2);

    assert.deepStrictEqual(result, expected);
  });
});

describe("hd()", () => {
  it("returns the head of the list", () => {
    const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)])
    const result = Kernel.hd(list)
    const expected = Type.integer(1)

    assert.deepStrictEqual(result, expected);
  })
})

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

describe("is_function()", () => {
  it("returns boxed true if the term is of boxed anonymous function type", () => {
    const term = Type.anonymousFunction(() => { return Type.integer(1) })
    const result = Kernel.is_function(term)

    assertBoxedTrue(result)
  })

  it("returns boxed false if the term is not of boxed anonymous function type", () => {
    const term = Type.integer(1)
    const result = Kernel.is_function(term)

    assertBoxedFalse(result)
  })
})

describe("put_in()", () => {
  it("puts value nested 1 level deep", () => {
    let data = Type.map();
    data = Map.put(data, Type.atom("test_key"), Type.string("abc"));

    const keys = Type.list([Type.atom("test_key")]);
    const result = Kernel.put_in(data, keys, Type.string("xyz"));

    let expected = Type.map();
    expected = Map.put(expected, Type.atom("test_key"), Type.string("xyz"));

    assert.deepStrictEqual(result, expected);
  });

  it("puts value nested more than 1 level deep", () => {
    let level2Data = Type.map();
    level2Data = Map.put(
      level2Data,
      Type.atom("test_key_2"),
      Type.string("abc")
    );

    let level1Data = Type.map();
    level1Data = Map.put(level1Data, Type.atom("test_key_1"), level2Data);

    const keys = Type.list([Type.atom("test_key_1"), Type.atom("test_key_2")]);
    const result = Kernel.put_in(level1Data, keys, Type.string("xyz"));

    let expectedLevel2Data = Type.map();
    expectedLevel2Data = Map.put(
      expectedLevel2Data,
      Type.atom("test_key_2"),
      Type.string("xyz")
    );

    let expectedLevel1Data = Type.map();
    expectedLevel1Data = Map.put(
      expectedLevel1Data,
      Type.atom("test_key_1"),
      expectedLevel2Data
    );

    assert.deepStrictEqual(result, expectedLevel1Data);
  });
});

describe("$subtract_lists()", () => {
  it("returns the left list if there are no matching elems in the right list", () => {
    const left = Type.list([Type.integer(1), Type.integer(2)]);
    const right = Type.list([Type.integer(3), Type.integer(4)]);
    const result = Kernel.$subtract_lists(left, right);

    assert.deepStrictEqual(result, left);
  });

  it("removes the first occurrence of an element on the left list for each element on the right", () => {
    const left = Type.list([
      Type.integer(1),
      Type.integer(2),
      Type.integer(3),
      Type.integer(1),
      Type.integer(2),
      Type.integer(3),
      Type.integer(1),
    ]);

    const right = Type.list([
      Type.integer(1),
      Type.integer(3),
      Type.integer(3),
      Type.integer(4),
    ]);

    const result = Kernel.$subtract_lists(left, right);

    const expected = Type.list([
      Type.integer(2),
      Type.integer(1),
      Type.integer(2),
      Type.integer(1),
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    const left = Type.list([Type.integer(1)]);
    const right = Type.list([Type.integer(2)]);
    const result = Kernel.$subtract_lists(left, right);

    assertFrozen(result);
  });
});

describe("tl()", () => {
  it("returns the tail of the list", () => {
    const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)])
    const result = Kernel.tl(list)
    const expected = Type.list([Type.integer(2), Type.integer(3)])

    assert.deepStrictEqual(result, expected);
  })
})

describe("to_string()", () => {
  it("converts boxed atom to boxed string", () => {
    const value = Type.atom("abc");

    const result = Kernel.to_string(value);
    const expected = Type.string("abc");

    assert.deepStrictEqual(result, expected);
  });

  it("converts boxed boolean to boxed string", () => {
    const value = Type.boolean(true);

    const result = Kernel.to_string(value);
    const expected = Type.string("true");

    assert.deepStrictEqual(result, expected);
  });

  it("converts boxed float to boxed string", () => {
    const value = Type.float(1.234);

    const result = Kernel.to_string(value);
    const expected = Type.string("1.234");

    assert.deepStrictEqual(result, expected);
  });

  it("converts boxed integer to boxed string", () => {
    const value = Type.integer(1);

    const result = Kernel.to_string(value);
    const expected = Type.string("1");

    assert.deepStrictEqual(result, expected);
  });

  it("returns the given arg if it is a boxed string", () => {
    const value = Type.string("abc");
    const result = Kernel.to_string(value);

    assert.deepStrictEqual(result, value);
  });

  it("converts boxed binary to boxed string", () => {
    const value = Type.binary([Type.string("abc"), Type.string("xyz")]);

    const result = Kernel.to_string(value);
    const expected = Type.string("abcxyz");

    assert.deepStrictEqual(result, expected);
  });

  it("converts boxed nil to boxed string", () => {
    const value = Type.nil();

    const result = Kernel.to_string(value);
    const expected = Type.string("");

    assert.deepStrictEqual(result, expected);
  });

  it("throws an error for not implemented types", () => {
    const value = { type: "not implemented", value: "test" };
    const expectedMessage =
      'Kernel.to_string(): boxedValue = {"type":"not implemented","value":"test"}';

    assert.throw(
      () => {
        Kernel.to_string(value);
      },
      HologramNotImplementedError,
      expectedMessage
    );
  });
});

describe("$unary_negative()", () => {
  it("negates the given value", () => {
    const value = Type.integer(123);

    const result = Kernel.$unary_negative(value);
    const expected = Type.integer(-123);

    assert.deepStrictEqual(result, expected);
  });
});
