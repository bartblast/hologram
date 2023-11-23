"use strict";

import {
  assert,
  linkModules,
  unlinkModules,
} from "../../assets/js/test_support.mjs";

import Renderer from "../../assets/js/renderer.mjs";
import Type from "../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

describe("renderDOM()", () => {
  it("text node", () => {
    const node = Type.tuple([Type.atom("text"), Type.bitstring("abc")]);
    const context = Type.map([]);
    const slots = Type.keywordList([]);
    const result = Renderer.renderDOM(node, context, slots);

    assert.equal(result, "abc");
  });
});
