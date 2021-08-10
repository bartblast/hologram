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

describe("evaluateAttributeValue()", () => {
  it("expression", () => {
    const value = {
      type: "expression",
      callback: (state) => {
        return {
          type: "tuple",
          data: [
            {
              type: "string",
              value: `test-${state.testKey}`
            }
          ]
        }
      }
    }
  
    const state = {testKey: "expression-value"}
    const result = DOM.evaluateAttributeValue(value, state)

    assert.equal(result, "test-expression-value")
  })

  it("non-expression", () => {
    const result = DOM.evaluateAttributeValue("test-value", {})
    assert.equal(result, "test-value")
  })
})