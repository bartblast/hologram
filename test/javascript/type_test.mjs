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

describe("bitstring()", () => {
  describe("different number of segments", () => {
    it("builds empty bitstring without segments", () => {
      const result = Type.bitstring([]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("builds single-segment bitstring", () => {
      const segment = Type.bitstringSegment(Type.integer(1), {
        size: Type.integer(1),
        unit: 1n,
      });
      const result = Type.bitstring([segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("builds multiple-segment bitstring", () => {
      const segment = Type.bitstringSegment(Type.integer(1), {
        size: Type.integer(1),
        unit: 1n,
      });
      const result = Type.bitstring([segment, segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1, 1]),
      };

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("bitstring segment type", () => {
    it("builds a segment from bitstring", () => {
      const integerSegment = Type.bitstringSegment(Type.integer(1), {
        size: Type.integer(1),
      });

      const bitstring = Type.bitstring([integerSegment]);
      const bitstringSegment = Type.bitstringSegment(bitstring);
      const result = Type.bitstring([bitstringSegment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1]),
      };

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("integer segment type", () => {
    it("builds a segment from positive integer without clamping", () => {
      // 170 (8 bits) -> 170 (8 bits)
      // 170 == 0b10101010

      const segment = Type.bitstringSegment(Type.integer(170), {});
      const result = Type.bitstring([segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1, 0, 1, 0, 1, 0, 1, 0]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("builds a segment from positive integer with clamping to 8 bits", () => {
      // 4010 (12 bits) -> 170 (8 bits)
      // 4010 == 0b111110101010
      // 170 == 0b10101010

      const segment = Type.bitstringSegment(Type.integer(4010), {});
      const result = Type.bitstring([segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1, 0, 1, 0, 1, 0, 1, 0]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("builds a segment from positive integer with clamping to 9 bits", () => {
      // 4010 (12 bits) -> 426 (9 bits)
      // 4010 == 0b111110101010
      // 426 == 0b110101010

      const segment = Type.bitstringSegment(Type.integer(4010), {
        size: Type.integer(9),
      });
      const result = Type.bitstring([segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1, 1, 0, 1, 0, 1, 0, 1, 0]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("builds a segment from negative integer without clamping", () => {
      // -22 (8 bits) -> 234 (8 bits)
      // -22 == 0b11101010
      // 234 == 0b11101010

      const segment = Type.bitstringSegment(Type.integer(-22), {});
      const result = Type.bitstring([segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1, 1, 1, 0, 1, 0, 1, 0]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("builds a segment from negative integer with clamping to 8 bits", () => {
      // -86 (12 bits) -> 170 (8 bits)
      // -86 == 0b111110101010
      // 170 == 0b10101010

      const segment = Type.bitstringSegment(Type.integer(-86), {});
      const result = Type.bitstring([segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1, 0, 1, 0, 1, 0, 1, 0]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("builds a segment from negative integer with clamping to 9 bits", () => {
      // -86 (12 bits) -> 426 (9 bits)
      // -86 == 0b111110101010
      // 426 == 0b110101010

      const segment = Type.bitstringSegment(Type.integer(-86), {
        size: Type.integer(9),
      });
      const result = Type.bitstring([segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1, 1, 0, 1, 0, 1, 0, 1, 0]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("takes into account the segment's unit value when calculating the number of bits to keep", () => {
      // 4010 (12 bits) -> 42 (6 bits)
      // 4010 == 0b111110101010
      // 42 == 0b101010

      const segment = Type.bitstringSegment(Type.integer(4010), {
        size: Type.integer(2),
        unit: 3n,
      });
      const result = Type.bitstring([segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1, 0, 1, 0, 1, 0]),
      };

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("errors", () => {
    it("raises ArgumentError if there is a mismatch between segment declared type and runtime type", () => {
      const segment = Type.bitstringSegment(Type.float(123.45), {
        type: "integer",
      });

      assert.throw(
        () => {
          Type.bitstring([segment]);
        },
        Error,
        "(ArgumentError) construction of binary failed: segment 1 of type 'integer': expected an integer but got: 123.45"
      );
    });
  });
});

describe("bitstringSegment()", () => {
  it("builds bitstring segment spec when no modifiers are given", () => {
    const result = Type.bitstringSegment(Type.integer(123));

    const expected = {
      value: {type: "integer", value: 123n},
      type: null,
      size: null,
      unit: null,
      signedness: null,
      endianness: null,
    };

    assert.deepStrictEqual(result, expected);
  });

  it("builds bitstring segment spec when all modifiers given", () => {
    const result = Type.bitstringSegment(Type.integer(123), {
      endianness: "little",
      signedness: "unsigned",
      unit: 3,
      size: Type.integer(8),
      type: "integer",
    });

    const expected = {
      value: {type: "integer", value: 123n},
      type: "integer",
      size: Type.integer(8),
      unit: 3,
      signedness: "unsigned",
      endianness: "little",
    };

    assert.deepStrictEqual(result, expected);
  });

  it("builds bitstring segment spec when a single modifier is given", () => {
    const result = Type.bitstringSegment(Type.integer(123), {
      signedness: "unsigned",
    });

    const expected = {
      value: {type: "integer", value: 123n},
      type: null,
      size: null,
      unit: null,
      signedness: "unsigned",
      endianness: null,
    };

    assert.deepStrictEqual(result, expected);
  });
});

describe("boolean()", () => {
  it("returns boxed true value", () => {
    const result = Type.boolean(true);
    const expected = {type: "atom", value: "true"};

    assert.deepStrictEqual(result, expected);
  });

  it("returns boxed false value", () => {
    const result = Type.boolean(false);
    const expected = {type: "atom", value: "false"};

    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    assertFrozen(Type.boolean(true));
  });
});

describe("consPattern()", () => {
  let head, tail, result;

  beforeEach(() => {
    head = Type.integer(1);
    tail = Type.list([Type.integer(2), Type.integer(3)]);
    result = Type.consPattern(head, tail);
  });

  it("returns cons pattern", () => {
    const expected = {type: "cons_pattern", head: head, tail: tail};
    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    assertFrozen(result);
  });
});

describe("encodeMapKey()", () => {
  it("encodes boxed atom value as map key", () => {
    const boxed = Type.atom("abc");
    const result = Type.encodeMapKey(boxed);

    assert.equal(result, "atom(abc)");
  });

  it("encodes empty boxed bitstring value as map key", () => {
    const segment = Type.bitstringSegment(Type.integer(0), {
      size: Type.integer(0),
    });
    const boxed = Type.bitstring([segment]);
    const result = Type.encodeMapKey(boxed);

    assert.equal(result, "bitstring()");
  });

  it("encodes non-empty boxed bitstring value as map key", () => {
    // 170 == 0b10101010

    const segment = Type.bitstringSegment(Type.integer(170), {});
    const boxed = Type.bitstring([segment]);
    const result = Type.encodeMapKey(boxed);

    assert.equal(result, "bitstring(10101010)");
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
  it("returns boxed integer value given JavaScript integer", () => {
    const result = Type.integer(1);
    const expected = {type: "integer", value: 1n};

    assert.deepStrictEqual(result, expected);
  });

  it("returns boxed integer value given JavaScript bigint", () => {
    const result = Type.integer(1n);
    const expected = {type: "integer", value: 1n};

    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    assertFrozen(Type.integer(1));
  });
});

describe("isAtom()", () => {
  it("returns true for boxed atom value", () => {
    const arg = Type.atom("test");
    const result = Type.isAtom(arg);

    assert.isTrue(result);
  });

  it("returns false for values of type other than boxed atom", () => {
    const arg = Type.integer(123);
    const result = Type.isAtom(arg);

    assert.isFalse(result);
  });
});

describe("isConsPattern()", () => {
  it("returns true if the given object is a boxed cons pattern", () => {
    const head = Type.integer(1);
    const tail = Type.list([Type.integer(2), Type.integer(3)]);
    const result = Type.isConsPattern(Type.consPattern(head, tail));

    assert.isTrue(result);
  });

  it("returns false if the given object is not a boxed cons pattern", () => {
    const result = Type.isConsPattern(Type.atom("abc"));
    assert.isFalse(result);
  });
});

describe("isFalse()", () => {
  it("returns true for boxed false value", () => {
    const arg = Type.atom("false");
    const result = Type.isFalse(arg);

    assert.isTrue(result);
  });

  it("returns false for boxed true value", () => {
    const arg = Type.atom("true");
    const result = Type.isFalse(arg);

    assert.isFalse(result);
  });

  it("returns false for values of types other than boxed atom", () => {
    const arg = Type.integer(123);
    const result = Type.isFalse(arg);

    assert.isFalse(result);
  });
});

describe("isFloat()", () => {
  it("returns true for boxed float value", () => {
    const result = Type.isFloat(Type.float(1.23));
    assert.isTrue(result);
  });

  it("returns false for values of types other than boxed float", () => {
    const result = Type.isFloat(Type.atom("abc"));
    assert.isFalse(result);
  });
});

describe("isInteger()", () => {
  it("returns true for boxed integer value", () => {
    const result = Type.isInteger(Type.integer(123));
    assert.isTrue(result);
  });

  it("returns false for values of types other than boxed integer", () => {
    const result = Type.isInteger(Type.atom("abc"));
    assert.isFalse(result);
  });
});

describe("isList()", () => {
  it("returns true for boxed list value", () => {
    const list = Type.list([Type.integer(1), Type.integer(2)]);
    const result = Type.isList(list);

    assert.isTrue(result);
  });

  it("returns false for values of types other than boxed list", () => {
    const result = Type.isList(Type.atom("abc"));
    assert.isFalse(result);
  });
});

describe("isMap()", () => {
  it("returns true for boxed map value", () => {
    const map = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    const result = Type.isMap(map);

    assert.isTrue(result);
  });

  it("returns false for values of types other than boxed map", () => {
    const result = Type.isMap(Type.atom("abc"));
    assert.isFalse(result);
  });
});

describe("isNumber()", () => {
  it("returns true for boxed floats", () => {
    const arg = Type.float(1.23);
    const result = Type.isNumber(arg);

    assert.isTrue(result);
  });

  it("returns true for boxed integers", () => {
    const arg = Type.integer(1);
    const result = Type.isNumber(arg);

    assert.isTrue(result);
  });

  it("returns false for boxed types other than float or integer", () => {
    const arg = Type.atom("abc");
    const result = Type.isNumber(arg);

    assert.isFalse(result);
  });
});

describe("isTrue()", () => {
  it("returns true for boxed true value", () => {
    const arg = Type.atom("true");
    const result = Type.isTrue(arg);

    assert.isTrue(result);
  });

  it("returns false for boxed false value", () => {
    const arg = Type.atom("false");
    const result = Type.isTrue(arg);

    assert.isFalse(result);
  });

  it("returns false for values of types other than boxed atom", () => {
    const arg = Type.integer(123);
    const result = Type.isTrue(arg);

    assert.isFalse(result);
  });
});

describe("isVariablePattern()", () => {
  it("returns true if the given object is a boxed variable pattern", () => {
    const result = Type.isVariablePattern(Type.variablePattern("abc"));
    assert.isTrue(result);
  });

  it("returns false if the given object is not a boxed variable pattern", () => {
    const result = Type.isVariablePattern(Type.atom("abc"));
    assert.isFalse(result);
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

describe("variablePattern()", () => {
  it("returns variable pattern", () => {
    const result = Type.variablePattern("test");
    const expected = {type: "variable_pattern", name: "test"};

    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    assertFrozen(Type.variablePattern("test"));
  });
});
