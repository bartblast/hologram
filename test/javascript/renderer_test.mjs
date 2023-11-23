"use strict";

import {
  assert,
  elixirKernelToString1,
  linkModules,
  unlinkModules,
} from "../../assets/js/test_support.mjs";

import Renderer from "../../assets/js/renderer.mjs";
import Type from "../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

describe("renderDOM()", () => {
  const context = Type.map([]);
  const slots = Type.keywordList([]);

  it("text node", () => {
    const node = Type.tuple([Type.atom("text"), Type.bitstring("abc")]);
    const result = Renderer.renderDOM(node, context, slots);

    assert.equal(result, "abc");
  });

  it("expression node", () => {
    const node = Type.tuple([Type.atom("expression"), Type.integer(123)]);
    const result = Renderer.renderDOM(node, context, slots);

    assert.equal(result, "123");
  });
});
