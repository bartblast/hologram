"use strict";

import {
  assert,
  assertBoxedError,
  buildClientStruct,
  elixirHologramComponentClientStruct0,
  linkModules,
  unlinkModules,
  vnode,
} from "../../assets/js/test_support.mjs";

import {defineHologramTestFixturesTemplateRendererModule1} from "./fixtures/template/renderer/module_1.mjs";
import {defineHologramTestFixturesTemplateRendererModule16} from "./fixtures/template/renderer/module_16.mjs";
import {defineHologramTestFixturesTemplateRendererModule17} from "./fixtures/template/renderer/module_17.mjs";
import {defineHologramTestFixturesTemplateRendererModule18} from "./fixtures/template/renderer/module_18.mjs";
import {defineHologramTestFixturesTemplateRendererModule2} from "./fixtures/template/renderer/module_2.mjs";
import {defineHologramTestFixturesTemplateRendererModule3} from "./fixtures/template/renderer/module_3.mjs";
import {defineHologramTestFixturesTemplateRendererModule4} from "./fixtures/template/renderer/module_4.mjs";
import {defineHologramTestFixturesTemplateRendererModule51} from "./fixtures/template/renderer/module_51.mjs";
import {defineHologramTestFixturesTemplateRendererModule52} from "./fixtures/template/renderer/module_52.mjs";
import {defineHologramTestFixturesTemplateRendererModule7} from "./fixtures/template/renderer/module_7.mjs";
import {defineHologramTestFixturesTemplateRendererModule8} from "./fixtures/template/renderer/module_8.mjs";

import Renderer from "../../assets/js/renderer.mjs";
import Store from "../../assets/js/store.mjs";
import Type from "../../assets/js/type.mjs";

before(() => {
  linkModules();
  defineHologramTestFixturesTemplateRendererModule1();
  defineHologramTestFixturesTemplateRendererModule16();
  defineHologramTestFixturesTemplateRendererModule17();
  defineHologramTestFixturesTemplateRendererModule18();
  defineHologramTestFixturesTemplateRendererModule2();
  defineHologramTestFixturesTemplateRendererModule3();
  defineHologramTestFixturesTemplateRendererModule4();
  defineHologramTestFixturesTemplateRendererModule51();
  defineHologramTestFixturesTemplateRendererModule52();
  defineHologramTestFixturesTemplateRendererModule7();
  defineHologramTestFixturesTemplateRendererModule8();
});

after(() => unlinkModules());

const cid = Type.bitstring("my_component");
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

  it("with nested stateful components", () => {
    const cid3 = Type.bitstring("component_3");
    const cid7 = Type.bitstring("component_7");

    const node = Type.tuple([
      Type.atom("element"),
      Type.bitstring("div"),
      Type.list([
        Type.tuple([
          Type.bitstring("attr"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("value")]]),
        ]),
      ]),
      Type.list([
        Type.tuple([
          Type.atom("component"),
          Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module3"),
          Type.list([
            Type.tuple([
              Type.bitstring("cid"),
              Type.keywordList([[Type.atom("text"), cid3]]),
            ]),
          ]),
          Type.list([]),
        ]),
        Type.tuple([
          Type.atom("component"),
          Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module7"),
          Type.list([
            Type.tuple([
              Type.bitstring("cid"),
              Type.keywordList([[Type.atom("text"), cid7]]),
            ]),
          ]),
          Type.list([]),
        ]),
      ]),
    ]);

    Store.putComponentState(
      cid3,
      Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ]),
    );

    Store.putComponentState(
      cid7,
      Type.map([
        [Type.atom("c"), Type.integer(3)],
        [Type.atom("d"), Type.integer(4)],
      ]),
    );

    const result = Renderer.renderDom(node, context, slots);

    assert.deepStrictEqual(
      result,
      vnode("div", {attrs: {attr: "value"}}, [
        vnode("div", {attrs: {}}, ["state_a = 1, state_b = 2"]),
        vnode("div", {attrs: {}}, ["state_c = 3, state_d = 4"]),
      ]),
    );

    assert.deepStrictEqual(
      Store.data,
      Type.map([
        [
          cid3,
          buildClientStruct({
            state: Type.map([
              [Type.atom("a"), Type.integer(1)],
              [Type.atom("b"), Type.integer(2)],
            ]),
          }),
        ],
        [
          cid7,
          buildClientStruct({
            state: Type.map([
              [Type.atom("c"), Type.integer(3)],
              [Type.atom("d"), Type.integer(4)],
            ]),
          }),
        ],
      ]),
    );
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

  it("with components having a root node", () => {
    const cid3 = Type.bitstring("component_3");
    const cid7 = Type.bitstring("component_7");

    const nodes = Type.list([
      Type.tuple([Type.atom("text"), Type.bitstring("abc")]),
      Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module3"),
        Type.list([
          Type.tuple([
            Type.bitstring("cid"),
            Type.keywordList([[Type.atom("text"), cid3]]),
          ]),
        ]),
        Type.list([]),
      ]),
      Type.tuple([Type.atom("text"), Type.bitstring("xyz")]),
      Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module7"),
        Type.list([
          Type.tuple([
            Type.bitstring("cid"),
            Type.keywordList([[Type.atom("text"), cid7]]),
          ]),
        ]),
        Type.list([]),
      ]),
    ]);

    Store.putComponentState(
      cid3,
      Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ]),
    );

    Store.putComponentState(
      cid7,
      Type.map([
        [Type.atom("c"), Type.integer(3)],
        [Type.atom("d"), Type.integer(4)],
      ]),
    );

    const result = Renderer.renderDom(nodes, context, slots);

    assert.deepStrictEqual(result, [
      "abc",
      vnode("div", {attrs: {}}, ["state_a = 1, state_b = 2"]),
      "xyz",
      vnode("div", {attrs: {}}, ["state_c = 3, state_d = 4"]),
    ]);

    assert.deepStrictEqual(
      Store.data,
      Type.map([
        [
          cid3,
          buildClientStruct({
            state: Type.map([
              [Type.atom("a"), Type.integer(1)],
              [Type.atom("b"), Type.integer(2)],
            ]),
          }),
        ],
        [
          cid7,
          buildClientStruct({
            state: Type.map([
              [Type.atom("c"), Type.integer(3)],
              [Type.atom("d"), Type.integer(4)],
            ]),
          }),
        ],
      ]),
    );
  });

  it("with components not having a root node", () => {
    const cid51 = Type.bitstring("component_51");
    const cid52 = Type.bitstring("component_52");

    const nodes = Type.list([
      Type.tuple([Type.atom("text"), Type.bitstring("abc")]),
      Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module51"),
        Type.list([
          Type.tuple([
            Type.bitstring("cid"),
            Type.keywordList([[Type.atom("text"), cid51]]),
          ]),
        ]),
        Type.list([]),
      ]),
      Type.tuple([Type.atom("text"), Type.bitstring("xyz")]),
      Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module52"),
        Type.list([
          Type.tuple([
            Type.bitstring("cid"),
            Type.keywordList([[Type.atom("text"), cid52]]),
          ]),
        ]),
        Type.list([]),
      ]),
    ]);

    Store.putComponentState(
      cid51,
      Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ]),
    );

    Store.putComponentState(
      cid52,
      Type.map([
        [Type.atom("c"), Type.integer(3)],
        [Type.atom("d"), Type.integer(4)],
      ]),
    );

    const result = Renderer.renderDom(nodes, context, slots);

    assert.deepStrictEqual(result, [
      "abc",
      vnode("div", {attrs: {}}, ["state_a = 1"]),
      vnode("div", {attrs: {}}, ["state_b = 2"]),
      "xyz",
      vnode("div", {attrs: {}}, ["state_c = 3"]),
      vnode("div", {attrs: {}}, ["state_d = 4"]),
    ]);

    assert.deepStrictEqual(
      Store.data,
      Type.map([
        [
          cid51,
          buildClientStruct({
            state: Type.map([
              [Type.atom("a"), Type.integer(1)],
              [Type.atom("b"), Type.integer(2)],
            ]),
          }),
        ],
        [
          cid52,
          buildClientStruct({
            state: Type.map([
              [Type.atom("c"), Type.integer(3)],
              [Type.atom("d"), Type.integer(4)],
            ]),
          }),
        ],
      ]),
    );
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
          Type.keywordList([[Type.atom("text"), cid]]),
        ]),
      ]),
      Type.list([]),
    ]);

    const resultVDom = Renderer.renderDom(node, context, slots);
    const expectedVdom = [vnode("div", {attrs: {}}, ["abc"])];
    assert.deepStrictEqual(resultVDom, expectedVdom);

    const expectedStoreData = Type.map([
      [cid, elixirHologramComponentClientStruct0()],
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
          Type.keywordList([[Type.atom("text"), cid]]),
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
      [cid, elixirHologramComponentClientStruct0()],
    ]);

    assert.deepStrictEqual(Store.data, expectedStoreData);
  });

  it("with state, component has already been initialized", () => {
    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module3"),
      Type.list([
        Type.tuple([
          Type.bitstring("cid"),
          Type.keywordList([[Type.atom("text"), cid]]),
        ]),
      ]),
      Type.list([]),
    ]);

    const state = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    Store.putComponentState(cid, state);

    const resultVDom = Renderer.renderDom(node, context, slots);

    const expectedVdom = [
      vnode("div", {attrs: {}}, ["state_a = 1, state_b = 2"]),
    ];

    assert.deepStrictEqual(resultVDom, expectedVdom);

    assert.deepStrictEqual(
      Store.data,
      Type.map([[cid, buildClientStruct({state: state})]]),
    );
  });

  it("with state, component hasn't been initialized yet", () => {
    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module3"),
      Type.list([
        Type.tuple([
          Type.bitstring("cid"),
          Type.keywordList([[Type.atom("text"), cid]]),
        ]),
      ]),
      Type.list([]),
    ]);

    const resultVDom = Renderer.renderDom(node, context, slots);

    const expectedVdom = [
      vnode("div", {attrs: {}}, ["state_a = 11, state_b = 22"]),
    ];

    assert.deepStrictEqual(resultVDom, expectedVdom);

    assert.deepStrictEqual(
      Store.data,
      Type.map([
        [
          cid,
          buildClientStruct({
            state: Type.map([
              [Type.atom("a"), Type.integer(11)],
              [Type.atom("b"), Type.integer(22)],
            ]),
          }),
        ],
      ]),
    );
  });

  it("with props and state, give state priority over prop if there are name collisions", () => {
    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module4"),
      Type.list([
        Type.tuple([
          Type.bitstring("cid"),
          Type.keywordList([[Type.atom("text"), cid]]),
        ]),
        Type.tuple([
          Type.bitstring("b"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("prop_b")]]),
        ]),
        Type.tuple([
          Type.bitstring("c"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("prop_c")]]),
        ]),
      ]),
      Type.list([]),
    ]);

    const state = Type.map([
      [Type.atom("a"), Type.bitstring("state_a")],
      [Type.atom("b"), Type.bitstring("state_b")],
    ]);

    Store.putComponentState(cid, state);

    const resultVDom = Renderer.renderDom(node, context, slots);

    const expectedVdom = [
      vnode("div", {attrs: {}}, [
        "var_a = state_a, var_b = state_b, var_c = prop_c",
      ]),
    ];

    assert.deepStrictEqual(resultVDom, expectedVdom);

    assert.deepStrictEqual(
      Store.data,
      Type.map([[cid, buildClientStruct({state: state})]]),
    );
  });

  it("cast props", () => {
    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module16"),
      Type.list([
        Type.tuple([
          Type.bitstring("cid"),
          Type.keywordList([[Type.atom("text"), cid]]),
        ]),
        Type.tuple([
          Type.bitstring("prop_1"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("value_1")]]),
        ]),
        Type.tuple([
          Type.bitstring("prop_2"),
          Type.keywordList([
            [Type.atom("expression"), Type.tuple([Type.integer(2)])],
          ]),
        ]),
        Type.tuple([
          Type.bitstring("prop_3"),
          Type.keywordList([
            [Type.atom("text"), Type.bitstring("aaa")],
            [Type.atom("expression"), Type.tuple([Type.integer(2)])],
            [Type.atom("text"), Type.bitstring("bbb")],
          ]),
        ]),
        Type.tuple([
          Type.bitstring("prop_4"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("value_4")]]),
        ]),
      ]),
      Type.list([]),
    ]);

    Renderer.renderDom(node, context, slots);

    assert.deepStrictEqual(
      Store.data,
      Type.map([
        [
          cid,
          buildClientStruct({
            state: Type.map([
              [Type.atom("cid"), cid],
              [Type.atom("prop_1"), Type.bitstring("value_1")],
              [Type.atom("prop_2"), Type.integer(2)],
              [Type.atom("prop_3"), Type.bitstring("aaa2bbb")],
            ]),
          }),
        ],
      ]),
    );
  });

  it("with unregistered var used", () => {
    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module18"),
      Type.list([
        Type.tuple([
          Type.bitstring("cid"),
          Type.keywordList([[Type.atom("text"), cid]]),
        ]),
        Type.tuple([
          Type.bitstring("a"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("111")]]),
        ]),
        Type.tuple([
          Type.bitstring("c"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("333")]]),
        ]),
      ]),
      Type.list([]),
    ]);

    Store.putComponentState(
      cid,
      Type.map([[Type.atom("b"), Type.integer(222)]]),
    );

    assertBoxedError(
      () => Renderer.renderDom(node, context, slots),
      "KeyError",
      'key :c not found in: %{cid: "my_component", a: "111", b: 222}',
    );
  });
});

describe("default slot", () => {
  it("with single node", () => {
    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module8"),
      Type.list([]),
      Type.keywordList([[Type.atom("text"), Type.bitstring("123")]]),
    ]);

    const result = Renderer.renderDom(node, context, slots);

    assert.deepStrictEqual(result, ["abc123xyz"]);
  });

  it("with multiple nodes", () => {
    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module8"),
      Type.list([]),
      Type.keywordList([
        [Type.atom("text"), Type.bitstring("123")],
        [Type.atom("expression"), Type.tuple([Type.integer(456)])],
      ]),
    ]);

    const result = Renderer.renderDom(node, context, slots);

    assert.deepStrictEqual(result, ["abc123456xyz"]);
  });
});
