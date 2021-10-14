"use strict";

import { assert } from "./support/commons";
import DOM from "../../assets/js/hologram/dom";
import Type from "../../assets/js/hologram/type";

describe("buildTextVNode()", () => {
  it("builds text vnode", () => {
    const textNode = Type.textNode("test")
    const result = DOM.buildTextVNode(textNode)

    assert.deepStrictEqual(result, ["test"])
  })
})