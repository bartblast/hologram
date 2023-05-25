"use strict";

import {assert, assertFrozen} from "../../assets/js/test_support.mjs";
import Utils from "../../assets/js/utils.mjs";

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

describe("indefiniteArticle()", () => {
  it("returns 'a' indefinite article", () => {
    assert.equal(Utils.indefiniteArticle("float"), "a");
  });

  it("returns 'an' indefinite article", () => {
    assert.equal(Utils.indefiniteArticle("integer"), "an");
  });
});
