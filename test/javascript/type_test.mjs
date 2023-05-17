"use strict";

import {assert, assertFrozen} from "../../assets/js/test_support.mjs";
import Type from "../../assets/js/type.mjs";

describe("atom()", () => {
  it("returns boxed atom value", () => {
    const result = Type.atom("test");
    const expected = {type: "atom", value: "test"};

    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    assertFrozen(Type.atom("test"));
  });
});

describe("encodeMapKey()", () => {
  it("encodes boxed atom value as map key", () => {
    const boxed = Type.atom("abc");
    const result = Type.encodeMapKey(boxed);

    assert.equal(result, "atom(abc)");
  });

  it("encodes boxed float value as map key", () => {
    const boxed = Type.float(1.23);
    const result = Type.encodeMapKey(boxed);

    assert.equal(result, "float(1.23)");
  });

  it("encodes boxed integer value as map key", () => {
    const boxed = Type.integer(123);
    const result = Type.encodeMapKey(boxed);

    assert.equal(result, "integer(123)");
  });

  it("encodes empty boxed list value as map key", () => {
    const result = Type.encodeMapKey(Type.list([]));

    assert.equal(result, "list()");
  });

  it("encodes non-empty boxed list value as map key", () => {
    const boxed = Type.list([Type.integer(1), Type.atom("b")]);
    const result = Type.encodeMapKey(boxed);

    assert.equal(result, "list(integer(1),atom(b))");
  });

  it("encodes empty boxed map value as map key", () => {
    const result = Type.encodeMapKey(Type.map([]));

    assert.equal(result, "map()");
  });

  it("encodes non-empty boxed map value as map key", () => {
    const boxed = Type.map([
      [Type.atom("b"), Type.integer(2)],
      [Type.atom("a"), Type.integer(1)],
    ]);

    const result = Type.encodeMapKey(boxed);

    assert.equal(result, "map(atom(a):integer(1),atom(b):integer(2))");
  });

  it("encodes boxed string value as map key", () => {
    const boxed = Type.string("abc");
    const result = Type.encodeMapKey(boxed);

    assert.equal(result, "string(abc)");
  });

  it("encodes empty boxed tuple value as map key", () => {
    const result = Type.encodeMapKey(Type.tuple([]));

    assert.equal(result, "tuple()");
  });

  it("encodes non-empty boxed tuple value as map key", () => {
    const boxed = Type.tuple([Type.integer(1), Type.atom("b")]);
    const result = Type.encodeMapKey(boxed);

    assert.equal(result, "tuple(integer(1),atom(b))");
  });
});

describe("float()", () => {
  it("returns boxed float value", () => {
    const result = Type.float(1.23);
    const expected = {type: "float", value: 1.23};

    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    assertFrozen(Type.float(1.0));
  });
});

describe("integer()", () => {
  it("returns boxed integer value", () => {
    const result = Type.integer(1);
    const expected = {type: "integer", value: 1};

    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    assertFrozen(Type.integer(1));
  });
});

describe("list()", () => {
  let data, expected, result;

  beforeEach(() => {
    data = [Type.integer(1), Type.integer(2)];

    result = Type.list(data);
    expected = {type: "list", data: data};
  });

  it("returns boxed list value", () => {
    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    assertFrozen(result);
  });
});

describe("map", () => {
  it("returns empty boxed map value", () => {
    const expected = {type: "map", data: {}};

    assert.deepStrictEqual(Type.map([]), expected);
  });

  it("returns non-empty boxed map value", () => {
    const data = [
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ];

    const expectedData = {
      "atom(a)": [Type.atom("a"), Type.integer(1)],
      "atom(b)": [Type.atom("b"), Type.integer(2)],
    };

    const expected = {type: "map", data: expectedData};

    assert.deepStrictEqual(Type.map(data), expected);
  });

  it("returns frozen object", () => {
    assertFrozen(Type.map([]));
  });
});

describe("string()", () => {
  it("returns boxed string value", () => {
    const result = Type.string("test");
    const expected = {type: "string", value: "test"};

    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    assertFrozen(Type.string("test"));
  });
});

describe("tuple()", () => {
  let data, expected, result;

  beforeEach(() => {
    data = [Type.integer(1), Type.integer(2)];

    result = Type.tuple(data);
    expected = {type: "tuple", data: data};
  });

  it("returns boxed tuple value", () => {
    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    assertFrozen(result);
  });
});

describe("variable()", () => {
  it("returns variable placeholder", () => {
    const result = Type.variable("test");
    const expected = {type: "variable", name: "test"};

    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    assertFrozen(Type.variable("test"));
  });
});
