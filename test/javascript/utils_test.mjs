"use strict";

import {
  assert,
  assertFrozen,
  assertNotFrozen,
  linkModules,
  unlinkModules,
} from "../../assets/js/test_support.mjs";
import Utils from "../../assets/js/utils.mjs";

before(() => linkModules());
after(() => unlinkModules());

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

describe("evaluate()", () => {
  let result;

  beforeEach(() => {
    result = Utils.evaluate("{value: 2 + 2}");
  });

  it("evaluates code", () => {
    assert.deepStrictEqual(result, {value: 4});
  });

  it("returns frozen object by default", () => {
    assertFrozen(result);
  });

  it("returns not frozen object if second arg is false", () => {
    result = Utils.evaluate("{value: 2 + 2}", false);
    assertNotFrozen(result);
  });
});

describe("freeze()", () => {
  it("freezes object and all of its properties recursively (deep freeze)", () => {
    let obj = {
      a: {
        c: {
          g: 1,
        },
        d: {
          h: 2,
        },
      },
      b: {
        e: {
          i: 3,
        },
        f: {
          j: 4,
        },
      },
    };

    Utils.freeze(obj);

    assertFrozen(obj.a);
    assertFrozen(obj.a.c);
    assertFrozen(obj.a.d);
    assertFrozen(obj.b);
    assertFrozen(obj.b.e);
    assertFrozen(obj.b.f);
  });
});

it("test CI", () => {
  assert.equal(1, 2);
});
