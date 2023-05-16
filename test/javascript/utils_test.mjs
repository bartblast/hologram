"use strict";

import { assertFrozen } from "../../assets/js/test_support.mjs";
import Utils from "../../assets/js/utils.mjs";

describe("freeze()", () => {
  it("freezes object and all of its properties recursively (deep freeze)", () => {
    let obj = {
      a: {
        c: {
          g: 1
        },
        d: {
          h: 2
        }
      },
      b: {
        e: {
          i: 3
        },
        f: {
          j: 4
        }
      },
    }

    Utils.freeze(obj)

    assertFrozen(obj.a)
    assertFrozen(obj.a.c)
    assertFrozen(obj.a.d)
    assertFrozen(obj.b)
    assertFrozen(obj.b.e)
    assertFrozen(obj.b.f)
  })
})