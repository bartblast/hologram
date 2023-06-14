"use strict";

import {
  assert,
  assertBoxedFalse,
  assertBoxedTrue,
  assertFrozen,
} from "../../../assets/js/test_support.mjs";

import Erlang from "../../../assets/js/erlang/erlang.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

describe("$261$258$261/2 (=:=)", () => {
  it("proxies to Interpreter.isStrictlyEqual/2 and casts the result to boxed boolean", () => {
    const left = Type.integer(1);
    const right = Type.integer(1);
    const result = Erlang.$261$258$261(left, right);
    const expected = Type.boolean(Interpreter.isStrictlyEqual(left, right));

    assert.deepStrictEqual(result, expected);
  });
});

describe("$261$261/2 (==)", () => {
  // non-number == non-number
  it("returns boxed true for a boxed non-number equal to another boxed non-number", () => {
    const left = Type.boolean(true);
    const right = Type.boolean(true);
    const result = Erlang.$261$261(left, right);

    assertBoxedTrue(result);
  });

  // non-number != non-number
  it("returns boxed false for a boxed non-number not equal to another boxed non-number", () => {
    const left = Type.boolean(true);
    const right = Type.string("abc");
    const result = Erlang.$261$261(left, right);

    assertBoxedFalse(result);
  });

  // integer == integer
  it("returns boxed true for a boxed integer equal to another boxed integer", () => {
    const left = Type.integer(1);
    const right = Type.integer(1);
    const result = Erlang.$261$261(left, right);

    assertBoxedTrue(result);
  });

  // integer != integer
  it("returns boxed false for a boxed integer not equal to another boxed integer", () => {
    const left = Type.integer(1);
    const right = Type.integer(2);
    const result = Erlang.$261$261(left, right);

    assertBoxedFalse(result);
  });

  // integer == float
  it("returns boxed true for a boxed integer equal to a boxed float", () => {
    const left = Type.integer(1);
    const right = Type.float(1.0);
    const result = Erlang.$261$261(left, right);

    assertBoxedTrue(result);
  });

  // integer != float
  it("returns boxed false for a boxed integer not equal to a boxed float", () => {
    const left = Type.integer(1);
    const right = Type.float(2.0);
    const result = Erlang.$261$261(left, right);

    assertBoxedFalse(result);
  });

  // integer != non-number
  it("returns boxed false when a boxed integer is compared to a boxed value of non-number type", () => {
    const left = Type.integer(1);
    const right = Type.string("1");
    const result = Erlang.$261$261(left, right);

    assertBoxedFalse(result);
  });

  // float == float
  it("returns boxed true for a boxed float equal to another boxed float", () => {
    const left = Type.float(1.0);
    const right = Type.float(1.0);
    const result = Erlang.$261$261(left, right);

    assertBoxedTrue(result);
  });

  // float != float
  it("returns boxed false for a boxed float not equal to another boxed float", () => {
    const left = Type.float(1.0);
    const right = Type.float(2.0);
    const result = Erlang.$261$261(left, right);

    assertBoxedFalse(result);
  });

  // float == integer
  it("returns boxed true for a boxed float equal to a boxed integer", () => {
    const left = Type.float(1.0);
    const right = Type.integer(1);
    const result = Erlang.$261$261(left, right);

    assertBoxedTrue(result);
  });

  // float != integer
  it("returns boxed false for a boxed float not equal to a boxed integer", () => {
    const left = Type.float(1.0);
    const right = Type.integer(2);
    const result = Erlang.$261$261(left, right);

    assertBoxedFalse(result);
  });

  // float != non-number
  it("returns boxed false when a boxed float is compared to a boxed value of non-number type", () => {
    const left = Type.float(1.0);
    const right = Type.string("1.0");
    const result = Erlang.$261$261(left, right);

    assertBoxedFalse(result);
  });

  it("returns frozen object", () => {
    const value = Type.integer(1);
    const result = Erlang.$261$261(value, value);

    assertFrozen(result);
  });
});

describe("hd/1", () => {
  it("proxies to Interpreter.head/1", () => {
    const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
    const result = Erlang.hd(list);
    const expected = Interpreter.head(list);

    assert.deepStrictEqual(result, expected);
  });
});

describe("is_atom/1", () => {
  it("proxies to Type.isAtom/1 and casts the result to boxed boolean", () => {
    const term = Type.atom("abc");
    const result = Erlang.is_atom(term);
    const expected = Type.boolean(Type.isAtom(term));

    assert.deepStrictEqual(result, expected);
  });
});

describe("is_float/1", () => {
  it("proxies to Type.isFloat/1 and casts the result to boxed boolean", () => {
    const term = Type.float(1.23);
    const result = Erlang.is_float(term);
    const expected = Type.boolean(Type.isFloat(term));

    assert.deepStrictEqual(result, expected);
  });
});

describe("is_integer/1", () => {
  it("proxies to Type.isInteger/1 and casts the result to boxed boolean", () => {
    const term = Type.integer(123);
    const result = Erlang.is_integer(term);
    const expected = Type.boolean(Type.isInteger(term));

    assert.deepStrictEqual(result, expected);
  });
});

describe("is_number/1", () => {
  it("proxies to Type.isNumber/1 and casts the result to boxed boolean", () => {
    const term = Type.integer(123);
    const result = Erlang.is_number(term);
    const expected = Type.boolean(Type.isNumber(term));

    assert.deepStrictEqual(result, expected);
  });
});

describe("length/1", () => {
  it("proxies to Interpreter.count/1 and casts the result to boxed integer", () => {
    const list = Type.list([Type.integer(1), Type.integer(2)]);
    const result = Erlang.length(list);
    const expected = Type.integer(Interpreter.count(list));

    assert.deepStrictEqual(result, expected);
  });
});

describe("tl/1", () => {
  it("proxies to Interpreter.tail/1", () => {
    const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
    const result = Erlang.tl(list);
    const expected = Interpreter.tail(list);

    assert.deepStrictEqual(result, expected);
  });
});
