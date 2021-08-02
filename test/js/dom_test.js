import { assert } from "./support/commons";
import DOM from "../../assets/js/hologram/dom";

describe("buildVNodeAttrs()", () => {
  it("builds vnode attrs", () => {
    let node = {
      attrs: {
        attr_1: {
          value: 1,
          modifiers: []
        },
        on_click: {
          value: 3,
          modifiers: []
        },
        attr_2: {
          value: 2,
          modifiers: []
        }
      }
    }

    let result = DOM.buildVNodeAttrs(node)

    let expected = {
      attr_1: 1,
      attr_2: 2
    }

    assert.deepStrictEqual(result, expected)
  })
})