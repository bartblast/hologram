"use strict";

import {assert} from "../../../assets/js/test_support.mjs";
import Erlang from "../../../assets/js/erlang/erlang.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

describe("$61$58$61/2 (=:=)", () => {
  it("proxies to Interpreter.isStrictlyEqual/2 and casts the result to boxed boolean", () => {
    const left = Type.integer(1);
    const right = Type.integer(1);
    const result = Erlang.$61$58$61(left, right);
    const expected = Type.boolean(Interpreter.isStrictlyEqual(left, right));

    assert.deepStrictEqual(result, expected);
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
