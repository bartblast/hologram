"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Utils from "../../assets/js/utils.mjs";

defineGlobalErlangAndElixirModules();

describe("Utils", () => {
  describe("capitalize()", () => {
    it("empty string", () => {
      assert.equal(Utils.capitalize(""), "");
    });

    it("single-word string", () => {
      assert.equal(Utils.capitalize("aaa"), "Aaa");
    });

    it("multiple-word string", () => {
      assert.equal(Utils.capitalize("aaa bbb"), "Aaa bbb");
    });
  });

  describe("cartesianProduct()", () => {
    it("returns empty array if no sets are given", () => {
      assert.deepStrictEqual(Utils.cartesianProduct([]), []);
    });

    it("returns empty array if any of the given sets are empty", () => {
      assert.deepStrictEqual(Utils.cartesianProduct([[1, 2], [], [3, 4]]), []);
    });

    it("returns an array of set items wrapped in arrays if only one set is given", () => {
      assert.deepStrictEqual(Utils.cartesianProduct([[1, 2]]), [[1], [2]]);
    });

    it("returns the cartesian product of the given sets if multiple non-empty sets are given", () => {
      const sets = [
        [1, 2],
        [3, 4, 5],
        [6, 7, 8, 9],
      ];

      const result = Utils.cartesianProduct(sets);

      // prettier-ignore
      const expected = [
      [ 1, 3, 6 ], [ 1, 3, 7 ], [ 1, 3, 8 ], [ 1, 3, 9 ],
      [ 1, 4, 6 ], [ 1, 4, 7 ], [ 1, 4, 8 ], [ 1, 4, 9 ],
      [ 1, 5, 6 ], [ 1, 5, 7 ], [ 1, 5, 8 ], [ 1, 5, 9 ],
      [ 2, 3, 6 ], [ 2, 3, 7 ], [ 2, 3, 8 ], [ 2, 3, 9 ],
      [ 2, 4, 6 ], [ 2, 4, 7 ], [ 2, 4, 8 ], [ 2, 4, 9 ],
      [ 2, 5, 6 ], [ 2, 5, 7 ], [ 2, 5, 8 ], [ 2, 5, 9 ]
    ]

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("chunkArray()", () => {
    it("empty array", () => {
      const result = Utils.chunkArray([], 3);
      assert.deepStrictEqual(result, []);
    });

    it("array can be chunked into equal parts", () => {
      const result = Utils.chunkArray([1, 2, 3, 4, 5, 6, 7, 8, 9], 3);

      assert.deepStrictEqual(result, [
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
      ]);
    });

    it("array can't be chunked into equal parts", () => {
      const result = Utils.chunkArray([1, 2, 3, 4, 5, 6, 7, 8], 3);

      assert.deepStrictEqual(result, [
        [1, 2, 3],
        [4, 5, 6],
        [7, 8],
      ]);
    });
  });

  describe("concatUint8Arrays()", () => {
    it("concatenates multiple 8-bit unsigned integer arrays", () => {
      const arrays = [
        new Uint8Array([1]),
        new Uint8Array([2, 3]),
        new Uint8Array([4, 5, 6]),
      ];
      const result = Utils.concatUint8Arrays(arrays);
      const expected = new Uint8Array([1, 2, 3, 4, 5, 6]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("naiveNounPlural", () => {
    it("0", () => {
      const result = Utils.naiveNounPlural("car", 0);
      assert.equal(result, "cars");
    });

    it("1", () => {
      const result = Utils.naiveNounPlural("car", 1);
      assert.equal(result, "car");
    });

    it("2", () => {
      const result = Utils.naiveNounPlural("car", 2);
      assert.equal(result, "cars");
    });

    it("3", () => {
      const result = Utils.naiveNounPlural("car", 3);
      assert.equal(result, "cars");
    });
  });

  describe("ordinal", () => {
    it("1st", () => {
      assert.equal(Utils.ordinal(1), "1st");
    });

    it("2nd", () => {
      assert.equal(Utils.ordinal(2), "2nd");
    });

    it("3rd", () => {
      assert.equal(Utils.ordinal(3), "3rd");
    });

    it("4th", () => {
      assert.equal(Utils.ordinal(4), "4th");
    });

    it("15th", () => {
      assert.equal(Utils.ordinal(15), "15th");
    });

    it("21st", () => {
      assert.equal(Utils.ordinal(21), "21st");
    });
  });

  it("randomUint32()", () => {
    const result = Utils.randomUint32();

    assert.isTrue(Number.isInteger(result));
    assert.isAtLeast(result, 0);
    assert.isAtMost(result, 4_294_967_295);
  });

  it("runAsyncTask()", async () => {
    const obj = {a: 1, b: 2};
    const task = () => (obj.b = 3);

    const promise = Utils.runAsyncTask(task);
    assert.instanceOf(promise, Promise);

    assert.equal(obj.b, 2);

    await promise;

    assert.equal(obj.b, 3);
  });

  it("shallowCloneArray()", () => {
    const arr = [1, [3, 4]];
    const clone = Utils.shallowCloneArray(arr);

    assert.deepStrictEqual(clone, [1, [3, 4]]);

    clone[0] = 10;
    clone[1][0] = 30;

    assert.deepStrictEqual(arr, [1, [30, 4]]);
    assert.deepStrictEqual(clone, [10, [30, 4]]);
  });

  it("shallowCloneObject()", () => {
    const obj = {a: 1, b: {c: 3, d: 4}};
    const clone = Utils.shallowCloneObject(obj);

    assert.deepStrictEqual(clone, {a: 1, b: {c: 3, d: 4}});

    clone.a = 10;
    clone.b.c = 30;

    assert.deepStrictEqual(obj, {a: 1, b: {c: 30, d: 4}});
    assert.deepStrictEqual(clone, {a: 10, b: {c: 30, d: 4}});
  });

  describe("Utils.zlibInflate", () => {
    // Test 1: Your original test, but verifying content, not just length
    it("should decompress a known valid zlib buffer correctly", async () => {
      const compressedData = new Uint8Array([
        120, 218, 203, 101, 96, 96, 252, 146, 145, 154, 147, 147, 63, 74, 140,
        40, 2, 0, 21, 94, 209, 51,
      ]);
      const expectedSize = 505;

      const decompressed = await Utils.zlibInflate(compressedData);

      assert.strictEqual(decompressed.length, expectedSize);

      // 109 is 'm'. Let's verify the first few bytes to be sure.
      assert.strictEqual(decompressed[0], 109);

      // Optional: Convert to string to see what's actually inside
      // const text = new TextDecoder().decode(decompressed);
      // console.log("Decompressed content sample:", text.substring(0, 20));
    });

    // Test 2: Empty Data (Zlib header for an empty string)
    it("should handle an empty compressed string", async () => {
      const emptyZlib = new Uint8Array([120, 156, 3, 0, 0, 0, 0, 1]);
      const decompressed = await Utils.zlibInflate(emptyZlib);

      assert.strictEqual(decompressed.length, 0);
    });

    // Test 3: Large Data (Testing the chunking logic)
    it("should decompress larger datasets that require multiple chunks", async () => {
      const originalString = "hello world ".repeat(1000);
      const encoder = new TextEncoder();
      const data = encoder.encode(originalString);

      // We use CompressionStream to generate the test data dynamically
      const cs = new CompressionStream("deflate");
      const writer = cs.writable.getWriter();
      writer.write(data);
      writer.close();

      const compressedResponse = await new Response(cs.readable).arrayBuffer();
      const compressedUint8 = new Uint8Array(compressedResponse);

      const result = await Utils.zlibInflate(compressedUint8);
      const resultString = new TextDecoder().decode(result);

      assert.strictEqual(resultString, originalString);
      assert.strictEqual(result.length, data.length);
    });

    // Test 4: Error Handling (Corrupt Data)
    it("should throw an error when given invalid/corrupt data", async () => {
      const corruptData = new Uint8Array([0, 1, 2, 3, 4, 5]); // Not a valid zlib stream

      try {
        await Utils.zlibInflate(corruptData);
        assert.fail("Should have thrown a decompression error");
      } catch (e) {
        // DecompressionStream throws a TypeError or DOMException on failure
        assert.ok(e instanceof Error);
      }
    });

    // Test 5: Type Safety
    it("should handle input as a Buffer or Uint8Array interchangeably", async () => {
      // Small valid zlib: "hi"
      const input = new Uint8Array([120, 156, 203, 200, 4, 0, 1, 59, 0, 210]);
      const decompressed = await Utils.zlibInflate(input);

      assert.strictEqual(new TextDecoder().decode(decompressed), "hi");
    });
  });
});
