"use strict";

import {
  assert,
  assertBoxedFalse,
  assertBoxedTrue,
  assertFrozen,
  cleanup,
} from "../support/commons";
beforeEach(() => cleanup());

import Enum from "../../../assets/js/hologram/elixir/enum";
import { HologramNotImplementedError } from "../../../assets/js/hologram/errors";
import Interpreter from "../../../assets/js/hologram/interpreter";
import Map from "../../../assets/js/hologram/elixir/map";
import Type from "../../../assets/js/hologram/type";

describe("concat()", () => {
  it("concatanates 2 enumerables to a boxed list", () => {
    let map = Type.map();
    map = Map.put(map, Type.atom("a"), Type.integer(1));
    map = Map.put(map, Type.atom("b"), Type.integer(2));

    const list = Type.list([Type.atom("c"), Type.integer(3)]);

    const result = Enum.concat(map, list);

    const expected = Type.list([
      Type.tuple([Type.atom("a"), Type.integer(1)]),
      Type.tuple([Type.atom("b"), Type.integer(2)]),
      Type.atom("c"),
      Type.integer(3),
    ]);

    assert.deepStrictEqual(result, expected);
    assertFrozen(result);
  });
});

describe("count()", () => {
  it("returns the size of the enumerable", () => {
    const enumerable = Type.list([
      Type.integer(1),
      Type.integer(2),
      Type.integer(3),
    ]);
    const result = Enum.count(enumerable);
    const expected = Type.integer(3);

    assert.deepStrictEqual(result, expected);
  });
});

describe("member$question()", () => {
  let list;

  beforeEach(() => {
    const elems = [Type.integer(1), Type.integer(2)];
    list = Type.list(elems);
  });

  it("returns boxed true boolean value if the list contains the element", () => {
    const elem = Type.integer(2);
    const result = Enum.member$question(list, elem);

    assertBoxedTrue(result);
  });

  it("returns boxed false boolean value if the list doesn't contain the element", () => {
    const elem = Type.integer(3);
    const result = Enum.member$question(list, elem);

    assertBoxedFalse(result);
  });

  it("uses strictly equal to operator", () => {
    const elems = [Type.float(1.0), Type.float(2.0), Type.float(3.0)];
    const list = Type.list(elems);

    const result1 = Enum.member$question(list, Type.integer(2));
    assertBoxedFalse(result1);

    const result2 = Enum.member$question(list, Type.float(2.0));
    assertBoxedTrue(result2);
  });

  it("throws an error for not implemented enumerable types", () => {
    const enumerable = { type: "not implemented", value: "test" };
    const elem = Type.integer(1);
    const expectedMessage =
      'Enum.member$question(): enumerable = {"type":"not implemented","value":"test"}, elem = {"type":"integer","value":1}';

    assert.throw(
      () => {
        Enum.member$question(enumerable, elem);
      },
      HologramNotImplementedError,
      expectedMessage
    );
  });
});

describe("reduce()", () => {
  it("invokes fun for each element in the enumerable with the accumulator", () => {
    const enumerable = Type.list([
      Type.integer(1),
      Type.integer(2),
      Type.integer(3),
    ]);
    const acc = Type.integer(10);

    const fun = Type.anonymousFunction(function (elem, acc) {
      return Interpreter.$addition_operator(
        acc,
        Interpreter.$multiplication_operator(elem, elem)
      );
    });

    const result = Enum.reduce(enumerable, acc, fun);
    const expected = Type.integer(24);

    assert.deepStrictEqual(result, expected);
  });
});

describe("to_list()", () => {
  it("returns the given arg if it is a boxed list", () => {
    const list = Type.list([Type.atom("a"), Type.integer(2)]);
    const result = Enum.to_list(list);

    assert.deepStrictEqual(result, list);
    assertFrozen(result);
  });

  it("converts a boxed map to a boxed list", () => {
    let map = Type.map();
    map = Map.put(map, Type.atom("a"), Type.integer(1));
    map = Map.put(map, Type.atom("b"), Type.integer(2));

    const result = Enum.to_list(map);

    const expected = Type.list([
      Type.tuple([Type.atom("a"), Type.integer(1)]),
      Type.tuple([Type.atom("b"), Type.integer(2)]),
    ]);

    assert.deepStrictEqual(result, expected);
    assertFrozen(result);
  });

  it("throws an error for not implemented enumerable types", () => {
    const enumerable = { type: "not implemented", value: "test" };
    const expectedMessage =
      'Enum.to_list(): enumerable = {"type":"not implemented","value":"test"}';
    assert.throw(
      () => {
        Enum.to_list(enumerable);
      },
      HologramNotImplementedError,
      expectedMessage
    );
  });
});
