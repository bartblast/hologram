"use strict";

import {
  assert,
  assertBoxedError,
  elixirHologramComponentClientStruct0,
  linkModules,
  unlinkModules,
  vnode,
} from "../../assets/js/test_support.mjs";

import {defineRendererFixtureModules} from "../../assets/js/test_fixtures.mjs";

import Renderer from "../../assets/js/renderer.mjs";
import Store from "../../assets/js/store.mjs";
import Type from "../../assets/js/type.mjs";
import Utils from "../../assets/js/utils.mjs";

before(() => {
  linkModules();
  defineRendererFixtureModules();
});

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

  it("non-void element, with children", () => {
    const node = Type.tuple([
      Type.atom("element"),
      Type.bitstring("div"),
      Type.list([]),
      Type.list([
        Type.tuple([
          Type.atom("element"),
          Type.bitstring("span"),
          Type.list([]),
          Type.keywordList([[Type.atom("text"), Type.bitstring("abc")]]),
        ]),
        Type.tuple([Type.atom("text"), Type.bitstring("xyz")]),
      ]),
    ]);

    const result = Renderer.renderDom(node, context, slots);

    const expected = vnode("div", {attrs: {}}, [
      vnode("span", {attrs: {}}, ["abc"]),
      "xyz",
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("void element, without attributes", () => {
    const node = Type.tuple([
      Type.atom("element"),
      Type.bitstring("img"),
      Type.list([]),
      Type.list([]),
    ]);

    const result = Renderer.renderDom(node, context, slots);
    const expected = vnode("img", {attrs: {}}, []);

    assert.deepStrictEqual(result, expected);
  });

  it("void element, with attributes", () => {
    const node = Type.tuple([
      Type.atom("element"),
      Type.bitstring("img"),
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
      "img",
      {attrs: {attr_1: "aaa", attr_2: "123", attr_3: "ccc987eee"}},
      [],
    );

    assert.deepStrictEqual(result, expected);
  });

  it("boolean attributes", () => {
    const node = Type.tuple([
      Type.atom("element"),
      Type.bitstring("img"),
      Type.list([
        Type.tuple([Type.bitstring("attr_1"), Type.keywordList([])]),
        Type.tuple([Type.bitstring("attr_2"), Type.keywordList([])]),
      ]),
      Type.list([]),
    ]);

    const result = Renderer.renderDom(node, context, slots);
    const expected = vnode("img", {attrs: {attr_1: true, attr_2: true}}, []);

    assert.deepStrictEqual(result, expected);
  });
});

describe("node list", () => {
  it("multiple nodes without merging", () => {
    const nodes = Type.list([
      Type.tuple([Type.atom("text"), Type.bitstring("aaa")]),
      Type.tuple([
        Type.atom("element"),
        Type.bitstring("div"),
        Type.list([]),
        Type.list([]),
      ]),
      Type.tuple([Type.atom("text"), Type.bitstring("bbb")]),
    ]);

    const result = Renderer.renderDom(nodes, context, slots);
    const expected = ["aaa", vnode("div", {attrs: {}}, []), "bbb"];

    assert.deepStrictEqual(result, expected);
  });

  it("multiple nodes with merging", () => {
    const nodes = Type.list([
      Type.tuple([Type.atom("text"), Type.bitstring("aaa")]),
      Type.tuple([Type.atom("expression"), Type.tuple([Type.integer(111)])]),
      Type.tuple([Type.atom("text"), Type.bitstring("bbb")]),
      Type.tuple([Type.atom("expression"), Type.tuple([Type.integer(222)])]),
    ]);

    const result = Renderer.renderDom(nodes, context, slots);

    assert.deepStrictEqual(result, ["aaa111bbb222"]);
  });

  it("nil nodes", () => {
    const nodes = Type.list([
      Type.tuple([Type.atom("text"), Type.bitstring("aaa")]),
      Type.nil(),
      Type.tuple([Type.atom("text"), Type.bitstring("bbb")]),
      Type.nil(),
    ]);

    const result = Renderer.renderDom(nodes, context, slots);

    assert.deepStrictEqual(result, ["aaabbb"]);
  });
});

describe("stateless component", () => {
  it("without props", () => {
    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module1"),
      Type.list([]),
      Type.list([]),
    ]);

    const result = Renderer.renderDom(node, context, slots);
    const expected = [vnode("div", {attrs: {}}, ["abc"])];

    assert.deepStrictEqual(result, expected);
  });

  it("with props", () => {
    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module2"),
      Type.list([
        Type.tuple([
          Type.bitstring("a"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("ddd")]]),
        ]),
        Type.tuple([
          Type.bitstring("b"),
          Type.keywordList([
            [Type.atom("expression"), Type.tuple([Type.integer(222)])],
          ]),
        ]),
        Type.tuple([
          Type.bitstring("c"),
          Type.keywordList([
            [Type.atom("text"), Type.bitstring("fff")],
            [Type.atom("expression"), Type.tuple([Type.integer(333)])],
            [Type.atom("text"), Type.bitstring("hhh")],
          ]),
        ]),
      ]),
      Type.list([]),
    ]);

    const result = Renderer.renderDom(node, context, slots);

    const expected = [
      vnode("div", {attrs: {}}, [
        "prop_a = ddd, prop_b = 222, prop_c = fff333hhh",
      ]),
    ];

    assert.deepStrictEqual(result, expected);
  });

  it("with unregistered var used", () => {
    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module17"),
      Type.list([
        Type.tuple([
          Type.bitstring("a"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("111")]]),
        ]),
        Type.tuple([
          Type.bitstring("b"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("222")]]),
        ]),
      ]),
      Type.list([]),
    ]);

    assertBoxedError(
      () => Renderer.renderDom(node, context, slots),
      "KeyError",
      'key :b not found in: %{a: "111"}',
    );
  });
});

describe("stateful component", () => {
  it("without props or state", () => {
    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module1"),
      Type.list([
        Type.tuple([
          Type.bitstring("cid"),
          Type.keywordList([
            [Type.atom("text"), Type.bitstring("my_component")],
          ]),
        ]),
      ]),
      Type.list([]),
    ]);

    const resultVDom = Renderer.renderDom(node, context, slots);
    const expectedVdom = [vnode("div", {attrs: {}}, ["abc"])];
    assert.deepStrictEqual(resultVDom, expectedVdom);

    const expectedStoreData = Type.map([
      [Type.bitstring("my_component"), elixirHologramComponentClientStruct0()],
    ]);

    assert.deepStrictEqual(Store.data, expectedStoreData);
  });

  it("with props", () => {
    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module2"),
      Type.list([
        Type.tuple([
          Type.bitstring("cid"),
          Type.keywordList([
            [Type.atom("text"), Type.bitstring("my_component")],
          ]),
        ]),
        Type.tuple([
          Type.bitstring("a"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("ddd")]]),
        ]),
        Type.tuple([
          Type.bitstring("b"),
          Type.keywordList([
            [Type.atom("expression"), Type.tuple([Type.integer(222)])],
          ]),
        ]),
        Type.tuple([
          Type.bitstring("c"),
          Type.keywordList([
            [Type.atom("text"), Type.bitstring("fff")],
            [Type.atom("expression"), Type.tuple([Type.integer(333)])],
            [Type.atom("text"), Type.bitstring("hhh")],
          ]),
        ]),
      ]),
      Type.list([]),
    ]);

    const resultVDom = Renderer.renderDom(node, context, slots);

    const expectedVdom = [
      vnode("div", {attrs: {}}, [
        "prop_a = ddd, prop_b = 222, prop_c = fff333hhh",
      ]),
    ];

    assert.deepStrictEqual(resultVDom, expectedVdom);

    const expectedStoreData = Type.map([
      [Type.bitstring("my_component"), elixirHologramComponentClientStruct0()],
    ]);

    assert.deepStrictEqual(Store.data, expectedStoreData);
  });
});
