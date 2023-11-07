"use strict";

import {
  assert,
  assertBoxedError,
  linkModules,
  unlinkModules,
} from "../../assets/js/test_support.mjs";
import Bitstring from "../../assets/js/bitstring.mjs";
import HologramInterpreterError from "../../assets/js/errors/interpreter_error.mjs";
import Type from "../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/bitstring_test.exs
// Always update both together.
describe("from()", () => {
  describe("number and structure of segments", () => {
    it("builds empty bitstring without segments", () => {
      const result = Bitstring.from([]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("builds single-segment bitstring", () => {
      const segment = Type.bitstringSegment(Type.integer(1), {
        size: Type.integer(1),
        type: "integer",
        unit: 1n,
      });

      const result = Bitstring.from([segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("builds multiple-segment bitstring", () => {
      const segment = Type.bitstringSegment(Type.integer(1), {
        size: Type.integer(1),
        type: "integer",
        unit: 1n,
      });

      const result = Bitstring.from([segment, segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1, 1]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("nested segments are flattened", () => {
      const segment1 = Type.bitstringSegment(Type.bitstring([1, 1]), {
        type: "bitstring",
      });

      const segment2 = Type.bitstringSegment(
        Type.bitstring([
          Type.bitstringSegment(Type.bitstring([1, 0]), {type: "bitstring"}),
          Type.bitstringSegment(Type.bitstring([1]), {type: "bitstring"}),
          Type.bitstringSegment(Type.bitstring([1, 0]), {type: "bitstring"}),
        ]),
        {type: "bitstring"},
      );

      const segment3 = Type.bitstringSegment(Type.bitstring([1, 1]), {
        type: "bitstring",
      });

      const result = Bitstring.from([segment1, segment2, segment3]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1, 1, 1, 0, 1, 1, 0, 1, 1]),
      };

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("defaults", () => {
    it("for bitstring value", () => {
      const segment = Type.bitstringSegment(Type.bitstring([1, 0, 1, 0]), {
        type: "bitstring",
      });

      const result = Bitstring.from([segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1, 0, 1, 0]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("for float value", () => {
      const segment = Type.bitstringSegment(Type.float(123.45), {
        type: "float",
      });

      const result = Bitstring.from([segment]);

      const expected = {
        type: "bitstring",
        // prettier-ignore
        bits: new Uint8Array([
                0, 1, 0, 0, 0, 0, 0, 0,
                0, 1, 0, 1, 1, 1, 1, 0,
                1, 1, 0, 1, 1, 1, 0, 0,
                1, 1, 0, 0, 1, 1, 0, 0,
                1, 1, 0, 0, 1, 1, 0, 0,
                1, 1, 0, 0, 1, 1, 0, 0,
                1, 1, 0, 0, 1, 1, 0, 0,
                1, 1, 0, 0, 1, 1, 0, 1
              ]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("for positive integer value that fits in 8 bits", () => {
      const segment = Type.bitstringSegment(Type.integer(170), {
        type: "integer",
      });

      const result = Bitstring.from([segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1, 0, 1, 0, 1, 0, 1, 0]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("for negative integer value that fits in 8 bits", () => {
      const segment = Type.bitstringSegment(Type.integer(-22), {
        type: "integer",
      });

      const result = Bitstring.from([segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1, 1, 1, 0, 1, 0, 1, 0]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("for positive integer value that fits in 12 bits", () => {
      const segment = Type.bitstringSegment(Type.integer(4010), {
        type: "integer",
      });

      const result = Bitstring.from([segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1, 0, 1, 0, 1, 0, 1, 0]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("for negative integer value that fits in 12 bits", () => {
      const segment = Type.bitstringSegment(Type.integer(-86), {
        type: "integer",
      });

      const result = Bitstring.from([segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1, 0, 1, 0, 1, 0, 1, 0]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("for string value", () => {
      const segment = Type.bitstringSegment(Type.string("全息图"), {
        type: "utf8",
      });

      const result = Bitstring.from([segment]);

      const expected = {
        type: "bitstring",
        // prettier-ignore
        bits: new Uint8Array([
            1, 1, 1, 0, 0, 1, 0, 1,
            1, 0, 0, 0, 0, 1, 0, 1,
            1, 0, 1, 0, 1, 0, 0, 0,
            1, 1, 1, 0, 0, 1, 1, 0,
            1, 0, 0, 0, 0, 0, 0, 1,
            1, 0, 1, 0, 1, 1, 1, 1,
            1, 1, 1, 0, 0, 1, 0, 1,
            1, 0, 0, 1, 1, 0, 1, 1,
            1, 0, 1, 1, 1, 1, 1, 0
          ]),
      };

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("binary type modifier", () => {
    it("with bitstring value when number of bits is divisible by 8", () => {
      const segment = Type.bitstringSegment(
        Type.bitstring([1, 0, 1, 0, 1, 0, 1, 0]),
        {type: "binary"},
      );

      const result = Bitstring.from([segment]);

      const expected = {
        type: "bitstring",
        bits: new Uint8Array([1, 0, 1, 0, 1, 0, 1, 0]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("with bitstring value when number of bits is not divisible by 8", () => {
      const segment = Type.bitstringSegment(Type.bitstring([1, 0, 1]), {
        type: "binary",
      });

      const expectedMessage = `construction of binary failed: segment 1 of type 'binary': the size of the value {"type":"bitstring","bits":{"0":1,"1":0,"2":1}} is not a multiple of the unit for the segment`;

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    it("with float value", () => {
      const segment = Type.bitstringSegment(Type.float(123.45), {
        type: "binary",
      });

      const expectedMessage =
        "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 123.45";

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    it("with integer value", () => {
      const segment = Type.bitstringSegment(Type.integer(170), {
        type: "binary",
      });

      const expectedMessage =
        "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 170";

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    it("with string value", () => {
      const segment = Type.bitstringSegment(Type.string("全息图"), {
        type: "binary",
      });

      const result = Bitstring.from([segment]);

      const expected = {
        type: "bitstring",
        // prettier-ignore
        bits: new Uint8Array([
            1, 1, 1, 0, 0, 1, 0, 1,
            1, 0, 0, 0, 0, 1, 0, 1,
            1, 0, 1, 0, 1, 0, 0, 0,
            1, 1, 1, 0, 0, 1, 1, 0,
            1, 0, 0, 0, 0, 0, 0, 1,
            1, 0, 1, 0, 1, 1, 1, 1,
            1, 1, 1, 0, 0, 1, 0, 1,
            1, 0, 0, 1, 1, 0, 1, 1,
            1, 0, 1, 1, 1, 1, 1, 0
          ]),
      };

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("bistring type modifier", () => {
    // Exactly the same as the defaults test for bitstring value.
    // it("with bitstring value")

    it("with float value", () => {
      const segment = Type.bitstringSegment(Type.float(123.45), {
        type: "bitstring",
      });

      const expectedMessage =
        "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 123.45";

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    it("with integer value", () => {
      const segment = Type.bitstringSegment(Type.integer(170), {
        type: "bitstring",
      });

      const expectedMessage =
        "construction of binary failed: segment 1 of type 'binary': expected a binary but got: 170";

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    it("with string value", () => {
      const segment = Type.bitstringSegment(Type.string("全息图"), {
        type: "bitstring",
      });

      const result = Bitstring.from([segment]);

      const expected = {
        type: "bitstring",
        // prettier-ignore
        bits: new Uint8Array([
            1, 1, 1, 0, 0, 1, 0, 1,
            1, 0, 0, 0, 0, 1, 0, 1,
            1, 0, 1, 0, 1, 0, 0, 0,
            1, 1, 1, 0, 0, 1, 1, 0,
            1, 0, 0, 0, 0, 0, 0, 1,
            1, 0, 1, 0, 1, 1, 1, 1,
            1, 1, 1, 0, 0, 1, 0, 1,
            1, 0, 0, 1, 1, 0, 1, 1,
            1, 0, 1, 1, 1, 1, 1, 0
          ]),
      };

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("float type modifier", () => {
    it("with bitstring value", () => {
      const segment = Type.bitstringSegment(Type.bitstring([1, 0, 1]), {
        type: "float",
      });

      const expectedMessage = `construction of binary failed: segment 1 of type 'float': expected a float or an integer but got: {"type":"bitstring","bits":{"0":1,"1":0,"2":1}}`;

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    // Exactly the same as the defaults test for float value.
    // it("with float value")

    it("with integer value", () => {
      const segment = Type.bitstringSegment(
        Type.integer(1234567890123456789n),
        {
          type: "float",
        },
      );

      const result = Bitstring.from([segment]);

      const expected = {
        type: "bitstring",
        // prettier-ignore
        bits: new Uint8Array([
                0, 1, 0, 0, 0, 0, 1, 1,
                1, 0, 1, 1, 0, 0, 0, 1,
                0, 0, 1, 0, 0, 0, 1, 0,
                0, 0, 0, 1, 0, 0, 0, 0,
                1, 1, 1, 1, 0, 1, 0, 0,
                0, 1, 1, 1, 1, 1, 0, 1,
                1, 1, 1, 0, 1, 0, 0, 1,
                1, 0, 0, 0, 0, 0, 0, 1
              ]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("with string value consisting of a single ASCI characters", () => {
      const segment = Type.bitstringSegment(Type.string("a"), {
        type: "float",
      });

      const expectedMessage = `construction of binary failed: segment 1 of type 'float': expected a float or an integer but got: "a"`;

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    it("with string value consisting of multiple ASCI characters", () => {
      const segment = Type.bitstringSegment(Type.string("abc"), {
        type: "float",
      });

      const expectedMessage = `construction of binary failed: segment 1 of type 'float': expected a float or an integer but got: "abc"`;

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });
  });

  describe("integer type modifier", () => {
    it("with bitstring value", () => {
      const segment = Type.bitstringSegment(Type.bitstring([1, 0, 1]), {
        type: "integer",
      });

      const expectedMessage = `construction of binary failed: segment 1 of type 'integer': expected an integer but got: {"type":"bitstring","bits":{"0":1,"1":0,"2":1}}`;

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    it("with float value", () => {
      const segment = Type.bitstringSegment(Type.float(123.45), {
        type: "integer",
      });

      const expectedMessage =
        "construction of binary failed: segment 1 of type 'integer': expected an integer but got: 123.45";

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    // Exactly the same as the defaults test for integer value.
    // it("with integer value")

    it("with string value consisting of a single ASCI characters", () => {
      const segment = Type.bitstringSegment(Type.string("a"), {
        type: "integer",
      });

      const expectedMessage = `construction of binary failed: segment 1 of type 'integer': expected an integer but got: "a"`;

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    it("with string value consisting of multiple ASCI characters", () => {
      const segment = Type.bitstringSegment(Type.string("abc"), {
        type: "integer",
      });

      const expectedMessage = `construction of binary failed: segment 1 of type 'integer': expected an integer but got: "abc"`;

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });
  });

  describe("utf8 type modifier", () => {
    it("with bitstring value", () => {
      // ?a == 97 == 0b01100001
      const segment = Type.bitstringSegment(
        Type.bitstring([0, 1, 1, 0, 0, 0, 0, 1]),
        {
          type: "utf8",
        },
      );

      const expectedMessage = `construction of binary failed: segment 1 of type 'utf8': expected a non-negative integer encodable as utf8 but got: {"type":"bitstring","bits":{"0":0,"1":1,"2":1,"3":0,"4":0,"5":0,"6":0,"7":1}}`;

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    it("with float value", () => {
      const segment = Type.bitstringSegment(Type.float(123.45), {
        type: "utf8",
      });

      const expectedMessage =
        "construction of binary failed: segment 1 of type 'utf8': expected a non-negative integer encodable as utf8 but got: 123.45";

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    it("with integer value that is a valid Unicode code point", () => {
      const segment = Type.bitstringSegment(Type.integer(20840), {
        type: "utf8",
      });

      const result = Bitstring.from([segment]);

      const expected = {
        type: "bitstring",
        // prettier-ignore
        bits: new Uint8Array([
                1, 1, 1, 0, 0, 1, 0, 1,
                1, 0, 0, 0, 0, 1, 0, 1,
                1, 0, 1, 0, 1, 0, 0, 0
              ]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("with integer value that is not a valid Unicode code point", () => {
      const segment = Type.bitstringSegment(Type.integer(1114113), {
        type: "utf8",
      });

      const expectedMessage =
        "construction of binary failed: segment 1 of type 'utf8': expected a non-negative integer encodable as utf8 but got: 1114113";

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    // Exactly the same as the defaults test for string value.
    // it("with literal string value")

    it("with runtime string value", () => {
      const segment = Type.bitstringSegment(Type.bitstring("abc"), {
        type: "utf8",
      });

      const expectedMessage = `construction of binary failed: segment 1 of type 'utf8': expected a non-negative integer encodable as utf8 but got: {"type":"bitstring","bits":{"0":0,"1":1,"2":1,"3":0,"4":0,"5":0,"6":0,"7":1,"8":0,"9":1,"10":1,"11":0,"12":0,"13":0,"14":1,"15":0,"16":0,"17":1,"18":1,"19":0,"20":0,"21":0,"22":1,"23":1}}`;

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });
  });

  describe("utf16 type modifier", () => {
    it("with bitstring value", () => {
      // ?a == 97 == 0b01100001
      const segment = Type.bitstringSegment(
        Type.bitstring([0, 1, 1, 0, 0, 0, 0, 1]),
        {
          type: "utf16",
        },
      );

      const expectedMessage = `construction of binary failed: segment 1 of type 'utf16': expected a non-negative integer encodable as utf16 but got: {"type":"bitstring","bits":{"0":0,"1":1,"2":1,"3":0,"4":0,"5":0,"6":0,"7":1}}`;

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    it("with integer value that is a valid Unicode code point", () => {
      const segment = Type.bitstringSegment(Type.integer(20840), {
        type: "utf16",
      });

      const result = Bitstring.from([segment]);

      const expected = {
        type: "bitstring",
        // prettier-ignore
        bits: new Uint8Array([
                0, 1, 0, 1, 0, 0, 0, 1,
                0, 1, 1, 0, 1, 0, 0, 0
              ]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("with integer value that is not a valid Unicode code point", () => {
      const segment = Type.bitstringSegment(Type.integer(1114113), {
        type: "utf16",
      });

      const expectedMessage =
        "construction of binary failed: segment 1 of type 'utf16': expected a non-negative integer encodable as utf16 but got: 1114113";

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    it("with literal string value", () => {
      const segment = Type.bitstringSegment(Type.string("全息图"), {
        type: "utf16",
      });

      const result = Bitstring.from([segment]);

      const expected = {
        type: "bitstring",
        // prettier-ignore
        bits: new Uint8Array([
            0, 1, 0, 1, 0, 0, 0, 1,
            0, 1, 1, 0, 1, 0, 0, 0,
            0, 1, 1, 0, 0, 0, 0, 0,
            0, 1, 1, 0, 1, 1, 1, 1,
            0, 1, 0, 1, 0, 1, 1, 0,
            1, 1, 1, 1, 1, 1, 1, 0
          ]),
      };

      assert.deepStrictEqual(result, expected);
    });

    it("with runtime string value", () => {
      const segment = Type.bitstringSegment(Type.bitstring("abc"), {
        type: "utf16",
      });

      const expectedMessage = `construction of binary failed: segment 1 of type 'utf16': expected a non-negative integer encodable as utf16 but got: {"type":"bitstring","bits":{"0":0,"1":1,"2":1,"3":0,"4":0,"5":0,"6":0,"7":1,"8":0,"9":1,"10":1,"11":0,"12":0,"13":0,"14":1,"15":0,"16":0,"17":1,"18":1,"19":0,"20":0,"21":0,"22":1,"23":1}}`;

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });
  });

  describe("utf32 type modifier", () => {
    it("with runtime string value", () => {
      const segment = Type.bitstringSegment(Type.bitstring("abc"), {
        type: "utf32",
      });

      const expectedMessage = `construction of binary failed: segment 1 of type 'utf32': expected a non-negative integer encodable as utf32 but got: {"type":"bitstring","bits":{"0":0,"1":1,"2":1,"3":0,"4":0,"5":0,"6":0,"7":1,"8":0,"9":1,"10":1,"11":0,"12":0,"13":0,"14":1,"15":0,"16":0,"17":1,"18":1,"19":0,"20":0,"21":0,"22":1,"23":1}}`;

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });
  });

  describe("values of not supported data types", () => {
    it("atom values are not supported", () => {
      const segment = Type.bitstringSegment(Type.atom("abc"), {
        type: "integer",
      });

      const expectedMessage =
        "construction of binary failed: segment 1 of type 'integer': expected an integer but got: :abc";

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    it("list values are not supported", () => {
      const segment = Type.bitstringSegment(
        Type.list([Type.integer(1), Type.integer(2)]),
        {type: "integer"},
      );

      const expectedMessage =
        "construction of binary failed: segment 1 of type 'integer': expected an integer but got: [1, 2]";

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });

    it("tuple values are not supported", () => {
      const segment = Type.bitstringSegment(
        Type.tuple([Type.integer(1), Type.integer(2)]),
        {type: "integer"},
      );

      const expectedMessage =
        "construction of binary failed: segment 1 of type 'integer': expected an integer but got: {1, 2}";

      assertBoxedError(
        () => Bitstring.from([segment]),
        "ArgumentError",
        expectedMessage,
      );
    });
  });
});

describe("merge()", () => {
  it("no bitstrings", () => {
    assert.deepStrictEqual(Bitstring.merge([]), Type.bitstring([]));
  });

  it("single bitstring", () => {
    const bitstring = Type.bitstring([1, 0, 1]);
    const result = Bitstring.merge([bitstring]);

    assert.deepStrictEqual(result, bitstring);
  });

  it("multiple bitstrings", () => {
    const bitstring1 = Type.bitstring([1, 1, 0]);
    const bitstring2 = Type.bitstring([1, 0, 1]);
    const bitstring3 = Type.bitstring([0, 1, 1]);

    const result = Bitstring.merge([bitstring1, bitstring2, bitstring3]);
    const expected = Type.bitstring([1, 1, 0, 1, 0, 1, 0, 1, 1]);

    assert.deepStrictEqual(result, expected);
  });
});

describe("resolveSegmentSize()", () => {
  it("size in float segment is specified", () => {
    const segment = Type.bitstringSegment(Type.float(1.23), {
      type: "float",
      size: Type.integer(7),
    });

    assert.equal(Bitstring.resolveSegmentSize(segment), 7n);
  });

  it("size in float segment is not specified", () => {
    const segment = Type.bitstringSegment(Type.float(1.23), {type: "float"});

    assert.equal(Bitstring.resolveSegmentSize(segment), 64n);
  });

  it("size in integer segment is specified", () => {
    const segment = Type.bitstringSegment(Type.integer(123), {
      type: "integer",
      size: Type.integer(7),
    });

    assert.equal(Bitstring.resolveSegmentSize(segment), 7n);
  });

  it("size in integer segment is not specified", () => {
    const segment = Type.bitstringSegment(Type.integer(123), {type: "integer"});

    assert.equal(Bitstring.resolveSegmentSize(segment), 8n);
  });

  it("size in segment of type other than float or integer is specified", () => {
    const segment = Type.bitstringSegment(Type.string("abc"), {
      type: "binary",
      size: Type.integer(7),
    });

    assert.throw(
      () => Bitstring.resolveSegmentSize(segment),
      HologramInterpreterError,
      "resolving binary segment size is not yet implemented in Hologram",
    );
  });

  it("size in segment of type other than float or integer is not specified", () => {
    const segment = Type.bitstringSegment(Type.string("abc"), {type: "binary"});

    assert.throw(
      () => Bitstring.resolveSegmentSize(segment),
      HologramInterpreterError,
      "resolving binary segment size is not yet implemented in Hologram",
    );
  });
});

describe("resolveSegmentUnit()", () => {
  it("unit in binary segment is specified", () => {
    const segment = Type.bitstringSegment(Type.bitstring("abc"), {
      type: "binary",
      unit: Type.integer(3),
    });

    assert.equal(Bitstring.resolveSegmentUnit(segment), 3n);
  });

  it("unit in binary segment is not specified", () => {
    const segment = Type.bitstringSegment(Type.bitstring("abc"), {
      type: "binary",
    });

    assert.equal(Bitstring.resolveSegmentUnit(segment), 8n);
  });

  it("unit in float segment is specified", () => {
    const segment = Type.bitstringSegment(Type.float(1.23), {
      type: "float",
      unit: Type.integer(3),
    });

    assert.equal(Bitstring.resolveSegmentUnit(segment), 3n);
  });

  it("unit in float segment is not specified", () => {
    const segment = Type.bitstringSegment(Type.float(1.23), {type: "float"});

    assert.equal(Bitstring.resolveSegmentUnit(segment), 1n);
  });

  it("unit in integer segment is specified", () => {
    const segment = Type.bitstringSegment(Type.integer(123), {
      type: "integer",
      unit: Type.integer(3),
    });

    assert.equal(Bitstring.resolveSegmentUnit(segment), 3n);
  });

  it("unit in integer segment is not specified", () => {
    const segment = Type.bitstringSegment(Type.integer(123), {type: "integer"});

    assert.equal(Bitstring.resolveSegmentUnit(segment), 1n);
  });

  it("unit in segment of type other than binary, float or integer is specified", () => {
    const segment = Type.bitstringSegment(Type.bitstring([1, 0, 1]), {
      type: "bitstring",
      unit: Type.integer(3),
    });

    assert.throw(
      () => Bitstring.resolveSegmentUnit(segment),
      HologramInterpreterError,
      "resolving bitstring segment unit is not yet implemented in Hologram",
    );
  });

  it("unit in segment of type other than binary, float or integer is not specified", () => {
    const segment = Type.bitstringSegment(Type.bitstring([1, 0, 1]), {
      type: "bitstring",
    });

    assert.throw(
      () => Bitstring.resolveSegmentUnit(segment),
      HologramInterpreterError,
      "resolving bitstring segment unit is not yet implemented in Hologram",
    );
  });
});

describe("toText()", () => {
  it("converts the bitstring to UTF-8 text if the number of its bits is divisible by 8", () => {
    const bitstring = Type.bitstring("全息图");
    const result = Bitstring.toText(bitstring);

    assert.equal(result, "全息图");
  });

  it("raises error when the number of bits in the bitstring is not divisible by 8", () => {
    const bitstring = Type.bitstring([1, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 1]);

    assert.throw(
      () => Bitstring.toText(bitstring),
      HologramInterpreterError,
      "number of bits must be divisible by 8, got 12 bits",
    );
  });
});

describe("validateCodePoint()", () => {
  it("integer that is a valid code point", () => {
    // a = 97
    assert.isTrue(Bitstring.validateCodePoint(97));
  });

  it("integer that is not a valid code point", () => {
    // Max Unicode code point value is 1,114,112
    assert.isFalse(Bitstring.validateCodePoint(1114113));
  });

  it("bigint that is a valid code point", () => {
    // a = 97
    assert.isTrue(Bitstring.validateCodePoint(97n));
  });

  it("bigint that is not a valid code point", () => {
    // Max Unicode code point value is 1,114,112
    assert.isFalse(Bitstring.validateCodePoint(1114113n));
  });

  it("not an integer or a bigint", () => {
    assert.isFalse(Bitstring.validateCodePoint("abc"));
  });
});

// TODO: cleanup
// describe("bitstring()", () => {
//   describe("size & unit modifiers", () => {
//     it("fails to build bitstring from 32-bit float segment", () => {
//       const segment = Type.bitstringSegment(Type.float(123.45), {
//         size: Type.integer(8),
//         unit: 4n,
//       });

//       assert.throw(
//         () => {
//           Type.bitstring([segment]);
//         },
//         Error,
//         "(Hologram.NotYetImplementedError) 32-bit float bitstring segments are not yet implemented in Hologram"
//       );
//     });

//     it("fails to build bitstring from 16-bit float segment", () => {
//       const segment = Type.bitstringSegment(Type.float(123.45), {
//         size: Type.integer(8),
//         unit: 2n,
//       });

//       assert.throw(
//         () => {
//           Type.bitstring([segment]);
//         },
//         Error,
//         "(Hologram.NotYetImplementedError) 16-bit float bitstring segments are not yet implemented in Hologram"
//       );
//     });

//     it("on positive 12-bit integer", () => {
//       // 4010 (12 bits) -> 42 (6 bits)
//       // 4010 == 0b111110101010
//       // 42 == 0b101010

//       const segment = Type.bitstringSegment(Type.integer(4010), {
//         size: Type.integer(2),
//         unit: 3n,
//       });
//       const result = Type.bitstring([segment]);

//       const expected = {
//         type: "bitstring",
//         bits: new Uint8Array([1, 0, 1, 0, 1, 0]),
//       };

//       assert.deepStrictEqual(result, expected);
//     });

//     it("on negative 12-bit integer", () => {
//       // -86 (12 bits) -> 42 (6 bits)
//       // -86 == 0b111110101010
//       // 42 == 0b101010

//       const segment = Type.bitstringSegment(Type.integer(-86), {
//         size: Type.integer(2),
//         unit: 3n,
//       });
//       const result = Type.bitstring([segment]);

//       const expected = {
//         type: "bitstring",
//         bits: new Uint8Array([1, 0, 1, 0, 1, 0]),
//       };

//       assert.deepStrictEqual(result, expected);
//     });

//     it("size modifier on string segment with binary type modifier", () => {
//       // ?a == 97 == 0b01100001
//       // ?b == 98 == 0b01100010
//       // ?c == 99 == 0b01100011

//       const segment = Type.bitstringSegment(Type.string("abc"), {
//         type: "binary",
//         size: Type.integer(2),
//       });

//       const result = Type.bitstring([segment]);

//       const expected = {
//         type: "bitstring",
//         // prettier-ignore
//         bits: new Uint8Array([
//           0, 1, 1, 0, 0, 0, 0, 1,
//           0, 1, 1, 0, 0, 0, 1, 0
//         ]),
//       };

//       assert.deepStrictEqual(result, expected);
//     });

//     it("ignores unit modifier on string segment with binary type modifier if size modifier is not specified", () => {
//       // ?a == 97 == 0b01100001
//       // ?b == 98 == 0b01100010
//       // ?c == 99 == 0b01100011

//       const segment = Type.bitstringSegment(Type.string("abc"), {
//         type: "binary",
//         unit: Type.integer(2),
//       });

//       const result = Type.bitstring([segment]);

//       const expected = {
//         type: "bitstring",
//         // prettier-ignore
//         bits: new Uint8Array([
//           0, 1, 1, 0, 0, 0, 0, 1,
//           0, 1, 1, 0, 0, 0, 1, 0,
//           0, 1, 1, 0, 0, 0, 1, 1
//         ]),
//       };

//       assert.deepStrictEqual(result, expected);
//     });

//     it("size modifier with unit modifier on string segment with binary type modifier", () => {
//       // ?a == 97 == 0b01100001
//       // ?b == 98 == 0b01100010
//       // ?c == 99 == 0b01100011

//       const segment = Type.bitstringSegment(Type.string("abc"), {
//         type: "binary",
//         size: Type.integer(4),
//         unit: 3n,
//       });

//       const result = Type.bitstring([segment]);

//       const expected = {
//         type: "bitstring",
//         // prettier-ignore
//         bits: new Uint8Array([
//           0, 1, 1, 0, 0, 0, 0, 1,
//           0, 1, 1, 0
//         ]),
//       };

//       assert.deepStrictEqual(result, expected);
//     });

//     it("requires size modifier if unit modifier is specified on float segment", () => {
//       const segment = Type.bitstringSegment(Type.float(123.45), {
//         unit: Type.integer(1),
//       });

//       assert.throw(
//         () => {
//           Type.bitstring([segment]);
//         },
//         Error,
//         "(CompileError) integer and float types require a size specifier if the unit specifier is given"
//       );
//     });

//     it("size modifier on string segment with utf8 type modifier", () => {
//       const segment = Type.bitstringSegment(Type.string("abcdefghi"), {
//         type: "utf8",
//         size: Type.integer(8),
//       });

//       assert.throw(
//         () => {
//           Type.bitstring([segment]);
//         },
//         Error,
//         "(CompileError) size and unit are not supported on utf types"
//       );
//     });

//     it("size modifier on string segment with utf16 type modifier", () => {
//       const segment = Type.bitstringSegment(Type.string("abcdefghi"), {
//         type: "utf16",
//         size: Type.integer(8),
//       });

//       assert.throw(
//         () => {
//           Type.bitstring([segment]);
//         },
//         Error,
//         "(CompileError) size and unit are not supported on utf types"
//       );
//     });

//     it("size modifier on string segment with utf32 type modifier", () => {
//       const segment = Type.bitstringSegment(Type.string("abcdefghi"), {
//         type: "utf32",
//         size: Type.integer(8),
//       });

//       assert.throw(
//         () => {
//           Type.bitstring([segment]);
//         },
//         Error,
//         "(CompileError) size and unit are not supported on utf types"
//       );
//     });

//     it("unit modifier on string segment with utf8 type modifier", () => {
//       const segment = Type.bitstringSegment(Type.string("abcdefghi"), {
//         type: "utf8",
//         unit: Type.integer(1),
//       });

//       assert.throw(
//         () => {
//           Type.bitstring([segment]);
//         },
//         Error,
//         "(CompileError) size and unit are not supported on utf types"
//       );
//     });

//     it("unit modifier on string segment with utf16 type modifier", () => {
//       const segment = Type.bitstringSegment(Type.string("abcdefghi"), {
//         type: "utf16",
//         unit: Type.integer(1),
//       });

//       assert.throw(
//         () => {
//           Type.bitstring([segment]);
//         },
//         Error,
//         "(CompileError) size and unit are not supported on utf types"
//       );
//     });

//     it("unit modifier on string segment with utf32 type modifier", () => {
//       const segment = Type.bitstringSegment(Type.string("abcdefghi"), {
//         type: "utf32",
//         unit: Type.integer(1),
//       });

//       assert.throw(
//         () => {
//           Type.bitstring([segment]);
//         },
//         Error,
//         "(CompileError) size and unit are not supported on utf types"
//       );
//     });
//   });

// describe("bitstringSegment()", () => {
//   it("fails to build float segment which is not 16-bit, 32-bit or 64-bit", () => {
//     const segment = Type.bitstringSegment(Type.float(123.45), {
//       size: Type.integer(11),
//     });

//     assert.throw(
//       () => {
//         Type.bitstring([segment]);
//       },
//       Error,
//       "(ArgumentError) construction of binary failed: segment 1 of type 'float': expected one of the supported sizes 16, 32, or 64 but got: 11"
//     );
//   });
// });
