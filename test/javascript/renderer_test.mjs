"use strict";

import {
  assert,
  linkModules,
  unlinkModules,
  vnode,
} from "../../assets/js/test_support.mjs";

import Renderer from "../../assets/js/renderer.mjs";
import Type from "../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

const context = Type.map([]);
const slots = Type.keywordList([]);

it("text node", () => {
  const node = Type.tuple([Type.atom("text"), Type.bitstring("abc")]);
  const result = Renderer.renderDom(node, context, slots);

  assert.equal(result, "abc");
});

it("expression node", () => {
  const node = Type.tuple([
    Type.atom("expression"),
    Type.tuple([Type.integer(123)]),
  ]);

  const result = Renderer.renderDom(node, context, slots);

  assert.equal(result, "123");
});

describe("element node", () => {
  it("non-void element, without attributes or children", () => {
    const node = Type.tuple([
      Type.atom("element"),
      Type.bitstring("div"),
      Type.list([]),
      Type.list([]),
    ]);

    const result = Renderer.renderDom(node, context, slots);
    const expected = vnode("div", {attrs: {}}, []);

    assert.deepStrictEqual(result, expected);
  });

  it("non-void element, with attributes", () => {
    const node = Type.tuple([
      Type.atom("element"),
      Type.bitstring("div"),
      Type.list([
        Type.tuple([
          Type.bitstring("attr_1"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("aaa")]]),
        ]),
        Type.tuple([
          Type.bitstring("attr_2"),
          Type.keywordList([
            [Type.atom("expression"), Type.tuple([Type.integer(123)])],
          ]),
        ]),
        Type.tuple([
          Type.bitstring("attr_3"),
          Type.keywordList([
            [Type.atom("text"), Type.bitstring("ccc")],
            [Type.atom("expression"), Type.tuple([Type.integer(987)])],
            [Type.atom("text"), Type.bitstring("eee")],
          ]),
        ]),
      ]),
      Type.list([]),
    ]);

    const result = Renderer.renderDom(node, context, slots);

    const expected = vnode(
      "div",
      {attrs: {attr_1: "aaa", attr_2: "123", attr_3: "ccc987eee"}},
      [],
    );

    assert.deepStrictEqual(result, expected);
  });
});

describe("node list", () => {
  it("text and expression nodes", () => {
    const nodes = Type.list([
      Type.tuple([Type.atom("text"), Type.bitstring("aaa")]),
      Type.tuple([Type.atom("expression"), Type.integer(111)]),
      Type.tuple([Type.atom("text"), Type.bitstring("bbb")]),
      Type.tuple([Type.atom("expression"), Type.integer(222)]),
    ]);

    const result = Renderer.renderDom(nodes, context, slots);

    assert.deepStrictEqual(result, ["aaa", "111", "bbb", "222"]);
  });

  it("nil nodes", () => {
    const nodes = Type.list([
      Type.tuple([Type.atom("text"), Type.bitstring("aaa")]),
      Type.nil(),
      Type.tuple([Type.atom("text"), Type.bitstring("bbb")]),
      Type.nil(),
    ]);

    const result = Renderer.renderDom(nodes, context, slots);

    assert.deepStrictEqual(result, ["aaa", "bbb"]);
  });
});
