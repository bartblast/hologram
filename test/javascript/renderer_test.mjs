// Based on Elixir Hologram.Template.RendererTest

"use strict";

import {
  assert,
  assertBoxedError,
  componentStructFixture,
  elixirHologramComponentStruct0,
  initStoreComponentStruct,
  linkModules,
  sinon,
  unlinkModules,
  vnode,
} from "./support/helpers.mjs";

import {defineLayoutFixture} from "./support/fixtures/layout_fixture.mjs";
import {defineModule1Fixture} from "./support/fixtures/template/renderer/module_1.mjs";
import {defineModule10Fixture} from "./support/fixtures/template/renderer/module_10.mjs";
import {defineModule11Fixture} from "./support/fixtures/template/renderer/module_11.mjs";
import {defineModule12Fixture} from "./support/fixtures/template/renderer/module_12.mjs";
import {defineModule14Fixture} from "./support/fixtures/template/renderer/module_14.mjs";
import {defineModule15Fixture} from "./support/fixtures/template/renderer/module_15.mjs";
import {defineModule16Fixture} from "./support/fixtures/template/renderer/module_16.mjs";
import {defineModule17Fixture} from "./support/fixtures/template/renderer/module_17.mjs";
import {defineModule18Fixture} from "./support/fixtures/template/renderer/module_18.mjs";
import {defineModule2Fixture} from "./support/fixtures/template/renderer/module_2.mjs";
import {defineModule21Fixture} from "./support/fixtures/template/renderer/module_21.mjs";
import {defineModule23Fixture} from "./support/fixtures/template/renderer/module_23.mjs";
import {defineModule24Fixture} from "./support/fixtures/template/renderer/module_24.mjs";
import {defineModule25Fixture} from "./support/fixtures/template/renderer/module_25.mjs";
import {defineModule26Fixture} from "./support/fixtures/template/renderer/module_26.mjs";
import {defineModule27Fixture} from "./support/fixtures/template/renderer/module_27.mjs";
import {defineModule3Fixture} from "./support/fixtures/template/renderer/module_3.mjs";
import {defineModule31Fixture} from "./support/fixtures/template/renderer/module_31.mjs";
import {defineModule32Fixture} from "./support/fixtures/template/renderer/module_32.mjs";
import {defineModule33Fixture} from "./support/fixtures/template/renderer/module_33.mjs";
import {defineModule34Fixture} from "./support/fixtures/template/renderer/module_34.mjs";
import {defineModule35Fixture} from "./support/fixtures/template/renderer/module_35.mjs";
import {defineModule36Fixture} from "./support/fixtures/template/renderer/module_36.mjs";
import {defineModule37Fixture} from "./support/fixtures/template/renderer/module_37.mjs";
import {defineModule38Fixture} from "./support/fixtures/template/renderer/module_38.mjs";
import {defineModule39Fixture} from "./support/fixtures/template/renderer/module_39.mjs";
import {defineModule4Fixture} from "./support/fixtures/template/renderer/module_4.mjs";
import {defineModule40Fixture} from "./support/fixtures/template/renderer/module_40.mjs";
import {defineModule41Fixture} from "./support/fixtures/template/renderer/module_41.mjs";
import {defineModule42Fixture} from "./support/fixtures/template/renderer/module_42.mjs";
import {defineModule43Fixture} from "./support/fixtures/template/renderer/module_43.mjs";
import {defineModule44Fixture} from "./support/fixtures/template/renderer/module_44.mjs";
import {defineModule45Fixture} from "./support/fixtures/template/renderer/module_45.mjs";
import {defineModule46Fixture} from "./support/fixtures/template/renderer/module_46.mjs";
import {defineModule47Fixture} from "./support/fixtures/template/renderer/module_47.mjs";
import {defineModule51Fixture} from "./support/fixtures/template/renderer/module_51.mjs";
import {defineModule52Fixture} from "./support/fixtures/template/renderer/module_52.mjs";
import {defineModule7Fixture} from "./support/fixtures/template/renderer/module_7.mjs";
import {defineModule8Fixture} from "./support/fixtures/template/renderer/module_8.mjs";
import {defineModule9Fixture} from "./support/fixtures/template/renderer/module_9.mjs";

import Hologram from "../../assets/js/hologram.mjs";
import Renderer from "../../assets/js/renderer.mjs";
import Store from "../../assets/js/store.mjs";
import Type from "../../assets/js/type.mjs";

before(() => {
  linkModules();

  defineLayoutFixture();
  defineModule1Fixture();
  defineModule10Fixture();
  defineModule11Fixture();
  defineModule12Fixture();
  defineModule14Fixture();
  defineModule15Fixture();
  defineModule16Fixture();
  defineModule17Fixture();
  defineModule18Fixture();
  defineModule2Fixture();
  defineModule21Fixture();
  defineModule23Fixture();
  defineModule24Fixture();
  defineModule25Fixture();
  defineModule26Fixture();
  defineModule27Fixture();
  defineModule3Fixture();
  defineModule31Fixture();
  defineModule32Fixture();
  defineModule33Fixture();
  defineModule34Fixture();
  defineModule35Fixture();
  defineModule36Fixture();
  defineModule37Fixture();
  defineModule38Fixture();
  defineModule39Fixture();
  defineModule4Fixture();
  defineModule40Fixture();
  defineModule41Fixture();
  defineModule42Fixture();
  defineModule43Fixture();
  defineModule44Fixture();
  defineModule45Fixture();
  defineModule46Fixture();
  defineModule47Fixture();
  defineModule51Fixture();
  defineModule52Fixture();
  defineModule7Fixture();
  defineModule8Fixture();
  defineModule9Fixture();
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

  it("filters out attributes that specify event handlers (starting with '$' character)", () => {
    const node = Type.tuple([
      Type.atom("element"),
      Type.bitstring("div"),
      Type.list([
        Type.tuple([
          Type.bitstring("attr_1"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("aaa")]]),
        ]),
        Type.tuple([
          Type.bitstring("$attr_2"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("bbb")]]),
        ]),
        Type.tuple([
          Type.bitstring("attr_3"),
          Type.keywordList([
            [Type.atom("expression"), Type.tuple([Type.integer(111)])],
          ]),
        ]),
        Type.tuple([
          Type.bitstring("$attr_4"),
          Type.keywordList([
            [Type.atom("expression"), Type.tuple([Type.integer(222)])],
          ]),
        ]),
        Type.tuple([
          Type.bitstring("attr_5"),
          Type.keywordList([
            [Type.atom("text"), Type.bitstring("ccc")],
            [Type.atom("expression"), Type.tuple([Type.integer(999)])],
            [Type.atom("text"), Type.bitstring("ddd")],
          ]),
        ]),
        Type.tuple([
          Type.bitstring("$attr_6"),
          Type.keywordList([
            [Type.atom("text"), Type.bitstring("eee")],
            [Type.atom("expression"), Type.tuple([Type.integer(888)])],
            [Type.atom("text"), Type.bitstring("fff")],
          ]),
        ]),
        Type.tuple([Type.bitstring("attr_7"), Type.keywordList([])]),
        Type.tuple([Type.bitstring("$attr_8"), Type.keywordList([])]),
      ]),
      Type.list([]),
    ]);

    const result = Renderer.renderDom(node, context, slots);
    const expected = vnode(
      "div",
      {
        attrs: {
          attr_1: "aaa",
          attr_3: "111",
          attr_5: "ccc999ddd",
          attr_7: true,
        },
      },
      [],
    );

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
          componentStructFixture({
            state: Type.map([
              [Type.atom("a"), Type.integer(1)],
              [Type.atom("b"), Type.integer(2)],
            ]),
          }),
        ],
        [
          cid7,
          componentStructFixture({
            state: Type.map([
              [Type.atom("c"), Type.integer(3)],
              [Type.atom("d"), Type.integer(4)],
            ]),
          }),
        ],
      ]),
    );
  });

  describe("client-only behaviour", () => {
    describe("event listeners", () => {
      it("single event listener", () => {
        const node = Type.tuple([
          Type.atom("element"),
          Type.bitstring("button"),
          Type.list([
            Type.tuple([
              Type.bitstring("$click"),
              Type.list([
                Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
              ]),
            ]),
          ]),
          Type.list([
            Type.tuple([Type.atom("text"), Type.bitstring("Click me")]),
          ]),
        ]);

        const result = Renderer.renderDom(node, context, slots);

        assert.deepStrictEqual(Object.keys(result.data.on), ["click"]);

        const stub = sinon
          .stub(Hologram, "handleEvent")
          .callsFake((_event, _operationSpecVdom) => null);

        result.data.on.click("dummyEvent");

        sinon.assert.calledWith(
          stub,
          "dummyEvent",
          Type.list([
            Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
          ]),
        );
      });

      it("multiple event listeners", () => {
        const node = Type.tuple([
          Type.atom("element"),
          Type.bitstring("input"),
          Type.list([
            Type.tuple([
              Type.bitstring("$click"),
              Type.list([
                Type.tuple([
                  Type.atom("text"),
                  Type.bitstring("my_click_action"),
                ]),
              ]),
            ]),
            Type.tuple([
              Type.bitstring("$focus"),
              Type.list([
                Type.tuple([
                  Type.atom("text"),
                  Type.bitstring("my_focus_action"),
                ]),
              ]),
            ]),
          ]),
          Type.list([]),
        ]);

        const result = Renderer.renderDom(node, context, slots);

        assert.deepStrictEqual(Object.keys(result.data.on), ["click", "focus"]);

        const stub = sinon
          .stub(Hologram, "handleEvent")
          .callsFake((_event, _operationSpecVdom) => null);

        result.data.on.click("dummyClickEvent");
        result.data.on.focus("dummyFocusEvent");

        sinon.assert.calledWith(
          stub,
          "dummyClickEvent",
          Type.list([
            Type.tuple([Type.atom("text"), Type.bitstring("my_click_action")]),
          ]),
        );

        sinon.assert.calledWith(
          stub,
          "dummyFocusEvent",
          Type.list([
            Type.tuple([Type.atom("text"), Type.bitstring("my_focus_action")]),
          ]),
        );
      });
    });
  });
});

// Some client tests are different than server tests.
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
          componentStructFixture({
            state: Type.map([
              [Type.atom("a"), Type.integer(1)],
              [Type.atom("b"), Type.integer(2)],
            ]),
          }),
        ],
        [
          cid7,
          componentStructFixture({
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
          componentStructFixture({
            state: Type.map([
              [Type.atom("a"), Type.integer(1)],
              [Type.atom("b"), Type.integer(2)],
            ]),
          }),
        ],
        [
          cid52,
          componentStructFixture({
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

    assert.deepStrictEqual(Store.data, Type.map([]));
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

    assert.deepStrictEqual(Store.data, Type.map([]));
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

// Some client tests are different than server tests.
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

    initStoreComponentStruct(cid);

    const resultVDom = Renderer.renderDom(node, context, slots);
    const expectedVdom = [vnode("div", {attrs: {}}, ["abc"])];
    assert.deepStrictEqual(resultVDom, expectedVdom);

    const expectedStoreData = Type.map([
      [cid, elixirHologramComponentStruct0()],
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

    initStoreComponentStruct(cid);

    const resultVDom = Renderer.renderDom(node, context, slots);

    const expectedVdom = [
      vnode("div", {attrs: {}}, [
        "prop_a = ddd, prop_b = 222, prop_c = fff333hhh",
      ]),
    ];

    assert.deepStrictEqual(resultVDom, expectedVdom);

    const expectedStoreData = Type.map([
      [cid, elixirHologramComponentStruct0()],
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
      Type.map([[cid, componentStructFixture({state: state})]]),
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
          componentStructFixture({
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
      Type.map([[cid, componentStructFixture({state: state})]]),
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

    initStoreComponentStruct(cid);

    const result = Renderer.renderDom(node, context, slots);

    assert.equal(
      result,
      'component vars = [cid: "my_component", prop_1: "value_1", prop_2: 2, prop_3: "aaa2bbb"]',
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

  it("nested components with slots, no slot tag in the top component template, not using vars", () => {
    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module8"),
      Type.list([]),
      Type.list([
        Type.tuple([
          Type.atom("component"),
          Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module9"),
          Type.list([]),
          Type.keywordList([[Type.atom("text"), Type.bitstring("789")]]),
        ]),
      ]),
    ]);

    const result = Renderer.renderDom(node, context, slots);

    assert.deepStrictEqual(result, ["abcdef789uvwxyz"]);
  });

  it("nested components with slots, no slot tag in the top component template, using vars", () => {
    const cid10 = Type.bitstring("component_10");
    const cid11 = Type.bitstring("component_11");
    const cid12 = Type.bitstring("component_12");

    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module10"),
      Type.list([
        Type.tuple([
          Type.bitstring("cid"),
          Type.keywordList([[Type.atom("text"), cid10]]),
        ]),
      ]),
      Type.list([]),
    ]);

    Store.putComponentState(
      cid10,
      Type.map([[Type.atom("a"), Type.integer(10)]]),
    );

    Store.putComponentState(
      cid11,
      Type.map([[Type.atom("a"), Type.integer(11)]]),
    );

    Store.putComponentState(
      cid12,
      Type.map([[Type.atom("a"), Type.integer(12)]]),
    );

    const result = Renderer.renderDom(node, context, slots);
    assert.deepStrictEqual(result, ["10,11,10,12,10"]);

    assert.deepStrictEqual(
      Store.data,
      Type.map([
        [
          cid10,
          componentStructFixture({
            state: Type.map([[Type.atom("a"), Type.integer(10)]]),
          }),
        ],
        [
          cid11,
          componentStructFixture({
            state: Type.map([[Type.atom("a"), Type.integer(11)]]),
          }),
        ],
        [
          cid12,
          componentStructFixture({
            state: Type.map([[Type.atom("a"), Type.integer(12)]]),
          }),
        ],
      ]),
    );
  });

  it("nested components with slots, slot tag in the top component template, not using vars", () => {
    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module31"),
      Type.list([]),
      Type.keywordList([[Type.atom("text"), Type.bitstring("abc")]]),
    ]);

    const result = Renderer.renderDom(node, context, slots);

    assert.deepStrictEqual(result, [
      "31a,32a,31b,33a,31c,abc,31x,33z,31y,32z,31z",
    ]);
  });

  it("nested components with slots, slot tag in the top component template, using vars", () => {
    const cid34 = Type.bitstring("component_34");
    const cid35 = Type.bitstring("component_35");
    const cid36 = Type.bitstring("component_36");

    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module34"),
      Type.list([
        Type.tuple([
          Type.bitstring("cid"),
          Type.keywordList([[Type.atom("text"), cid34]]),
        ]),
        Type.tuple([
          Type.bitstring("a"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("34a_prop")]]),
        ]),
      ]),
      Type.keywordList([[Type.atom("text"), Type.bitstring("abc")]]),
    ]);

    Store.putComponentState(
      cid34,
      Type.map([
        [Type.atom("cid"), cid34],
        [Type.atom("a"), Type.bitstring("34a_prop")],
        [Type.atom("b"), Type.bitstring("34b_state")],
        [Type.atom("c"), Type.bitstring("34c_state")],
        [Type.atom("x"), Type.bitstring("34x_state")],
        [Type.atom("y"), Type.bitstring("34y_state")],
        [Type.atom("z"), Type.bitstring("34z_state")],
      ]),
    );

    Store.putComponentState(
      cid35,
      Type.map([
        [Type.atom("cid"), cid35],
        [Type.atom("a"), Type.bitstring("35a_prop")],
        [Type.atom("z"), Type.bitstring("35z_state")],
      ]),
    );

    Store.putComponentState(
      cid36,
      Type.map([
        [Type.atom("cid"), cid36],
        [Type.atom("a"), Type.bitstring("36a_prop")],
        [Type.atom("z"), Type.bitstring("36z_state")],
      ]),
    );

    const result = Renderer.renderDom(node, context, slots);

    assert.deepStrictEqual(result, [
      "34a_prop,35a_prop,34b_state,36a_prop,34c_state,abc,34x_state,36z_state,34y_state,35z_state,34z_state",
    ]);

    assert.deepStrictEqual(
      Store.data,
      Type.map([
        [
          cid34,
          componentStructFixture({
            state: Type.map([
              [Type.atom("cid"), Type.bitstring("component_34")],
              [Type.atom("a"), Type.bitstring("34a_prop")],
              [Type.atom("b"), Type.bitstring("34b_state")],
              [Type.atom("c"), Type.bitstring("34c_state")],
              [Type.atom("x"), Type.bitstring("34x_state")],
              [Type.atom("y"), Type.bitstring("34y_state")],
              [Type.atom("z"), Type.bitstring("34z_state")],
            ]),
          }),
        ],
        [
          cid35,
          componentStructFixture({
            state: Type.map([
              [Type.atom("cid"), Type.bitstring("component_35")],
              [Type.atom("a"), Type.bitstring("35a_prop")],
              [Type.atom("z"), Type.bitstring("35z_state")],
            ]),
          }),
        ],
        [
          cid36,
          componentStructFixture({
            state: Type.map([
              [Type.atom("cid"), Type.bitstring("component_36")],
              [Type.atom("a"), Type.bitstring("36a_prop")],
              [Type.atom("z"), Type.bitstring("36z_state")],
            ]),
          }),
        ],
      ]),
    );
  });
});

describe("context", () => {
  it("emitted in page, accessed in component nested in page", () => {
    initStoreComponentStruct(Type.bitstring("layout"));

    Store.putComponentEmittedContext(
      Type.bitstring("page"),
      Type.map([
        [
          Type.tuple([Type.atom("my_scope"), Type.atom("my_key")]),
          Type.integer(123),
        ],
      ]),
    );

    const result = Renderer.renderPage(
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module39"),
      Type.map([]),
    );

    assert.deepStrictEqual(result, ["prop_aaa = 123"]);
  });

  it("emitted in page, accessed in component nested in layout", () => {
    initStoreComponentStruct(Type.bitstring("layout"));

    Store.putComponentEmittedContext(
      Type.bitstring("page"),
      Type.map([
        [
          Type.tuple([Type.atom("my_scope"), Type.atom("my_key")]),
          Type.integer(123),
        ],
      ]),
    );

    const result = Renderer.renderPage(
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module46"),
      Type.map([]),
    );

    assert.deepStrictEqual(result, ["prop_aaa = 123"]);
  });

  it("emitted in page, accessed in layout", () => {
    initStoreComponentStruct(Type.bitstring("layout"));

    Store.putComponentEmittedContext(
      Type.bitstring("page"),
      Type.map([
        [
          Type.tuple([Type.atom("my_scope"), Type.atom("my_key")]),
          Type.integer(123),
        ],
      ]),
    );

    const result = Renderer.renderPage(
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module40"),
      Type.map([]),
    );

    assert.deepStrictEqual(result, ["prop_aaa = 123"]);
  });

  it("emmited in layout, accessed in component nested in page", () => {
    initStoreComponentStruct(Type.bitstring("page"));

    Store.putComponentEmittedContext(
      Type.bitstring("layout"),
      Type.map([
        [
          Type.tuple([Type.atom("my_scope"), Type.atom("my_key")]),
          Type.integer(123),
        ],
      ]),
    );

    const result = Renderer.renderPage(
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module43"),
      Type.map([]),
    );

    assert.deepStrictEqual(result, ["prop_aaa = 123"]);
  });

  it("emitted in layout, accessed in component nested in layout", () => {
    initStoreComponentStruct(Type.bitstring("page"));

    Store.putComponentEmittedContext(
      Type.bitstring("layout"),
      Type.map([
        [
          Type.tuple([Type.atom("my_scope"), Type.atom("my_key")]),
          Type.integer(123),
        ],
      ]),
    );

    const result = Renderer.renderPage(
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module45"),
      Type.map([]),
    );

    assert.deepStrictEqual(result, ["prop_aaa = 123"]);
  });

  it("emitted in component, accessed in component", () => {
    const cid = Type.bitstring("component_37");

    Store.putComponentEmittedContext(
      cid,
      Type.map([
        [
          Type.tuple([Type.atom("my_scope"), Type.atom("my_key")]),
          Type.integer(123),
        ],
      ]),
    );

    const node = Type.tuple([
      Type.atom("component"),
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module37"),
      Type.list([
        Type.tuple([
          Type.bitstring("cid"),
          Type.keywordList([[Type.atom("text"), cid]]),
        ]),
      ]),
      Type.list([]),
    ]);

    const result = Renderer.renderDom(node, context, slots);

    assert.deepStrictEqual(result, ["prop_aaa = 123"]);
  });
});

describe("page", () => {
  it("inside layout slot", () => {
    initStoreComponentStruct(Type.bitstring("page"));
    initStoreComponentStruct(Type.bitstring("layout"));

    const result = Renderer.renderPage(
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module14"),
      Type.map([]),
    );

    assert.deepStrictEqual(result, [
      "layout template start, page template, layout template end",
    ]);
  });

  // This test case doesn't apply to the client renderer, because the client renderer receives already casted page params.
  // it("cast page params")

  it("cast layout explicit static props", () => {
    initStoreComponentStruct(Type.bitstring("page"));
    initStoreComponentStruct(Type.bitstring("layout"));

    const result = Renderer.renderPage(
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module25"),
      Type.map([]),
    );

    assert.deepStrictEqual(result, [
      'layout vars = [cid: "layout", prop_1: "prop_value_1", prop_3: "prop_value_3"]',
    ]);
  });

  it("cast layout props passed implicitely from page state", () => {
    Store.putComponentState(
      Type.bitstring("page"),
      Type.map([
        [Type.atom("prop_1"), Type.bitstring("prop_value_1")],
        [Type.atom("prop_2"), Type.bitstring("prop_value_2")],
        [Type.atom("prop_3"), Type.bitstring("prop_value_3")],
      ]),
    );

    initStoreComponentStruct(Type.bitstring("layout"));

    const result = Renderer.renderPage(
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module27"),
      Type.map([]),
    );

    assert.deepStrictEqual(result, [
      'layout vars = [cid: "layout", prop_1: "prop_value_1", prop_3: "prop_value_3"]',
    ]);
  });

  it("aggregate page vars, giving state vars priority over param vars when there are name conflicts", () => {
    Store.putComponentState(
      Type.bitstring("page"),
      Type.map([
        [Type.atom("key_2"), Type.bitstring("state_value_2")],
        [Type.atom("key_3"), Type.bitstring("state_value_3")],
      ]),
    );

    initStoreComponentStruct(Type.bitstring("layout"));

    const result = Renderer.renderPage(
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module21"),
      Type.map([
        [Type.atom("key_1"), Type.bitstring("param_value_1")],
        [Type.atom("key_2"), Type.bitstring("param_value_2")],
      ]),
    );

    assert.deepStrictEqual(result, [
      'page vars = [key_1: "param_value_1", key_2: "state_value_2", key_3: "state_value_3"]',
    ]);
  });

  it("aggregate layout vars, giving state vars priority over prop vars when there are name conflicts", () => {
    initStoreComponentStruct(Type.bitstring("page"));

    Store.putComponentState(
      Type.bitstring("layout"),
      Type.map([
        [Type.atom("key_2"), Type.bitstring("state_value_2")],
        [Type.atom("key_3"), Type.bitstring("state_value_3")],
      ]),
    );

    const result = Renderer.renderPage(
      Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module24"),
      Type.map([]),
    );

    assert.deepStrictEqual(result, [
      'layout vars = [cid: "layout", key_1: "prop_value_1", key_2: "state_value_2", key_3: "state_value_3"]',
    ]);
  });
});
