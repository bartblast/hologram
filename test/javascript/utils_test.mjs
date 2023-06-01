"use strict";

import {assert, assertFrozen} from "../../assets/js/test_support.mjs";
import Utils from "../../assets/js/utils.mjs";

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
