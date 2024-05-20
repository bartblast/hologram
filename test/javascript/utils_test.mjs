"use strict";

import {assert, linkModules, unlinkModules} from "./support/helpers.mjs";

import Type from "../../assets/js/type.mjs";
import Utils from "../../assets/js/utils.mjs";

describe("Utils", () => {
  before(() => linkModules());
  after(() => unlinkModules());

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

  it("evaluate()", () => {
    const result = Utils.evaluate("{value: 2 + 2}");
    assert.deepStrictEqual(result, {value: 4});
  });

  describe("serialize()", () => {
    it("JS integer", () => {
      assert.equal(Utils.serialize(123), "123");
    });

    it("JS string", () => {
      assert.equal(Utils.serialize("abc"), '"abc"');
    });

    it("JS non-negative BigInt", () => {
      assert.equal(Utils.serialize(123n), '"__bigint__:123"');
    });

    it("JS negative BigInt", () => {
      assert.equal(Utils.serialize(-123n), '"__bigint__:-123"');
    });

    it("JS non-nested object", () => {
      assert.equal(Utils.serialize({a: 1, b: 2}), '{"a":1,"b":2}');
    });

    it("JS nested object", () => {
      const term = {a: 1, b: 2, c: {d: 3, e: 4}};
      const expected = '{"a":1,"b":2,"c":{"d":3,"e":4}}';

      assert.equal(Utils.serialize(term), expected);
    });

    it("boxed integer", () => {
      const term = Type.integer(123);
      const expected = '{"type":"integer","value":"__bigint__:123"}';

      assert.equal(Utils.serialize(term), expected);
    });

    it("boxed float", () => {
      const term = Type.float(1.23);
      const expected = '{"type":"float","value":1.23}';

      assert.equal(Utils.serialize(term), expected);
    });

    it("boxed binary", () => {
      const term = Type.bitstring('a"bc');
      const expected = '"__string__:a\\"bc"';

      assert.equal(Utils.serialize(term), expected);
    });

    it("boxed bitstring that is not a binary", () => {
      const term = Type.bitstring([1, 0, 1, 0]);
      const expected = '{"type":"bitstring","bits":{"0":1,"1":0,"2":1,"3":0}}';

      assert.equal(Utils.serialize(term), expected);
    });
  });
});
