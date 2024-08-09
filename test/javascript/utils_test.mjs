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

  describe("cloneDeep()", () => {
    it("clones vars recursively (deep clone)", () => {
      const nested = {c: 3, d: 4};
      const obj = {a: 1, b: nested};
      const expected = {a: 1, b: nested};
      const result = Utils.cloneDeep(obj);

      assert.deepStrictEqual(result, expected);
      assert.notEqual(result.b, nested);
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
});
