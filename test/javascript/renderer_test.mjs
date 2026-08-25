// Based on Elixir Hologram.Template.RendererTest

"use strict";

import {
  assert,
  assertBoxedError,
  buildKeyErrorMsg,
  componentRegistryEntryFixture,
  contextFixture,
  defineRuntimeGlobals,
  initComponentRegistryEntry,
  sinon,
  vnode,
} from "./support/helpers.mjs";

import {defineLayoutFixture} from "./support/fixtures/layout_fixture.mjs";
import {defineModule1Fixture} from "./support/fixtures/renderer/module_1.mjs";
import {defineModule10Fixture} from "./support/fixtures/renderer/module_10.mjs";
import {defineModule11Fixture} from "./support/fixtures/renderer/module_11.mjs";
import {defineModule12Fixture} from "./support/fixtures/renderer/module_12.mjs";
import {defineModule14Fixture} from "./support/fixtures/renderer/module_14.mjs";
import {defineModule15Fixture} from "./support/fixtures/renderer/module_15.mjs";
import {defineModule16Fixture} from "./support/fixtures/renderer/module_16.mjs";
import {defineModule17Fixture} from "./support/fixtures/renderer/module_17.mjs";
import {defineModule18Fixture} from "./support/fixtures/renderer/module_18.mjs";
import {defineModule2Fixture} from "./support/fixtures/renderer/module_2.mjs";
import {defineModule21Fixture} from "./support/fixtures/renderer/module_21.mjs";
import {defineModule23Fixture} from "./support/fixtures/renderer/module_23.mjs";
import {defineModule24Fixture} from "./support/fixtures/renderer/module_24.mjs";
import {defineModule25Fixture} from "./support/fixtures/renderer/module_25.mjs";
import {defineModule26Fixture} from "./support/fixtures/renderer/module_26.mjs";
import {defineModule27Fixture} from "./support/fixtures/renderer/module_27.mjs";
import {defineModule3Fixture} from "./support/fixtures/renderer/module_3.mjs";
import {defineModule31Fixture} from "./support/fixtures/renderer/module_31.mjs";
import {defineModule32Fixture} from "./support/fixtures/renderer/module_32.mjs";
import {defineModule33Fixture} from "./support/fixtures/renderer/module_33.mjs";
import {defineModule34Fixture} from "./support/fixtures/renderer/module_34.mjs";
import {defineModule35Fixture} from "./support/fixtures/renderer/module_35.mjs";
import {defineModule36Fixture} from "./support/fixtures/renderer/module_36.mjs";
import {defineModule37Fixture} from "./support/fixtures/renderer/module_37.mjs";
import {defineModule38Fixture} from "./support/fixtures/renderer/module_38.mjs";
import {defineModule39Fixture} from "./support/fixtures/renderer/module_39.mjs";
import {defineModule4Fixture} from "./support/fixtures/renderer/module_4.mjs";
import {defineModule40Fixture} from "./support/fixtures/renderer/module_40.mjs";
import {defineModule41Fixture} from "./support/fixtures/renderer/module_41.mjs";
import {defineModule42Fixture} from "./support/fixtures/renderer/module_42.mjs";
import {defineModule43Fixture} from "./support/fixtures/renderer/module_43.mjs";
import {defineModule44Fixture} from "./support/fixtures/renderer/module_44.mjs";
import {defineModule45Fixture} from "./support/fixtures/renderer/module_45.mjs";
import {defineModule46Fixture} from "./support/fixtures/renderer/module_46.mjs";
import {defineModule47Fixture} from "./support/fixtures/renderer/module_47.mjs";
import {defineModule51Fixture} from "./support/fixtures/renderer/module_51.mjs";
import {defineModule52Fixture} from "./support/fixtures/renderer/module_52.mjs";
import {defineModule55Fixture} from "./support/fixtures/renderer/module_55.mjs";
import {defineModule56Fixture} from "./support/fixtures/renderer/module_56.mjs";
import {defineModule57Fixture} from "./support/fixtures/renderer/module_57.mjs";
import {defineModule58Fixture} from "./support/fixtures/renderer/module_58.mjs";
import {defineModule59Fixture} from "./support/fixtures/renderer/module_59.mjs";
import {defineModule60Fixture} from "./support/fixtures/renderer/module_60.mjs";
import {defineModule61Fixture} from "./support/fixtures/renderer/module_61.mjs";
import {defineModule62Fixture} from "./support/fixtures/renderer/module_62.mjs";
import {defineModule63Fixture} from "./support/fixtures/renderer/module_63.mjs";
import {defineModule64Fixture} from "./support/fixtures/renderer/module_64.mjs";
import {defineModule65Fixture} from "./support/fixtures/renderer/module_65.mjs";
import {defineModule66Fixture} from "./support/fixtures/renderer/module_66.mjs";
import {defineModule67Fixture} from "./support/fixtures/renderer/module_67.mjs";
import {defineModule68Fixture} from "./support/fixtures/renderer/module_68.mjs";
import {defineModule7Fixture} from "./support/fixtures/renderer/module_7.mjs";
import {defineModule76Fixture} from "./support/fixtures/renderer/module_76.mjs";
import {defineModule77Fixture} from "./support/fixtures/renderer/module_77.mjs";
import {defineModule78Fixture} from "./support/fixtures/renderer/module_78.mjs";
import {defineModule86Fixture} from "./support/fixtures/renderer/module_86.mjs";
import {defineModule87Fixture} from "./support/fixtures/renderer/module_87.mjs";
import {defineModule8Fixture} from "./support/fixtures/renderer/module_8.mjs";
import {defineModule89Fixture} from "./support/fixtures/renderer/module_89.mjs";
import {defineModule9Fixture} from "./support/fixtures/renderer/module_9.mjs";
import {defineModule91Fixture} from "./support/fixtures/renderer/module_91.mjs";
import {defineClientOnlyModule1Fixture} from "./support/fixtures/renderer/client_only/module_1.mjs";
import {defineClientOnlyModule2Fixture} from "./support/fixtures/renderer/client_only/module_2.mjs";

import Bitstring from "../../assets/js/bitstring.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
import EventListeners from "../../assets/js/event_listeners.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import InitActionQueue from "../../assets/js/init_action_queue.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import Once from "../../assets/js/once.mjs";
import Renderer from "../../assets/js/renderer.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

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
defineModule55Fixture();
defineModule56Fixture();
defineModule57Fixture();
defineModule58Fixture();
defineModule59Fixture();
defineModule60Fixture();
defineModule61Fixture();
defineModule62Fixture();
defineModule63Fixture();
defineModule64Fixture();
defineModule65Fixture();
defineModule66Fixture();
defineModule67Fixture();
defineModule68Fixture();
defineModule7Fixture();
defineModule76Fixture();
defineModule77Fixture();
defineModule78Fixture();
defineModule86Fixture();
defineModule87Fixture();
defineModule89Fixture();
defineModule8Fixture();
defineModule91Fixture();
defineModule9Fixture();
defineClientOnlyModule1Fixture();
defineClientOnlyModule2Fixture();

describe("Renderer", () => {
  beforeEach(() => {
    ComponentRegistry.clear();
  });

  const cid = Type.bitstring("my_component");
  const context = Type.map();
  const defaultTarget = Type.bitstring("my_default_target");
  const parentTagName = "div";
  const slots = Type.keywordList();

  const element = (tagName, childrenDom = []) =>
    Type.tuple([
      Type.atom("element"),
      Type.bitstring(tagName),
      Type.list(),
      Type.list(childrenDom),
    ]);

  // An element carrying the key of its place in the template, as the compiler writes it.
  const keyedElement = (tagName, index, childrenDom = []) =>
    Type.tuple([
      Type.atom("element"),
      Type.bitstring(tagName),
      Type.list([
        Type.tuple([
          Type.bitstring("$key"),
          Type.keywordList([
            [Type.atom("text"), Type.bitstring(`1a2b3c:${index}`)],
          ]),
        ]),
      ]),
      Type.list(childrenDom),
    ]);

  it("text node", () => {
    const node = Type.tuple([Type.atom("text"), Type.bitstring("abc")]);

    const result = Renderer.renderDom(
      node,
      context,
      slots,
      defaultTarget,
      parentTagName,
    );

    assert.equal(result, "abc");
  });

  describe("public comment node", () => {
    it("empty", () => {
      // <!---->
      const node = Type.tuple([Type.atom("public_comment"), Type.list()]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode("!", "");

      assert.deepStrictEqual(result, expected);
    });

    it("with single child", () => {
      // <!--<div></div>-->
      const node = Type.tuple([
        Type.atom("public_comment"),
        Type.list([
          Type.tuple([
            Type.atom("element"),
            Type.bitstring("div"),
            Type.list(),
            Type.list(),
          ]),
        ]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode("!", "<div></div>");

      assert.deepStrictEqual(result, expected);
    });

    it("with multiple children", () => {
      // <!--abc<div></div>-->
      const node = Type.tuple([
        Type.atom("public_comment"),
        Type.list([
          Type.tuple([Type.atom("text"), Type.bitstring("abc")]),
          Type.tuple([
            Type.atom("element"),
            Type.bitstring("div"),
            Type.list(),
            Type.list(),
          ]),
        ]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode("!", "abc<div></div>");

      assert.deepStrictEqual(result, expected);
    });

    it("numbers a repeated key in one children list", () => {
      // <span><div></div><div></div></span>, both divs written in one place of one template
      const node = element("span", [
        keyedElement("div", 0),
        keyedElement("div", 0),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(
        result.children.map((child) => child.key),
        ["1a2b3c:0", "1a2b3c:0:1"],
      );
    });

    // A loop's iterations are lists of their own, so each place of the body occurs once in each
    // of them - the repeat only exists in the children list they are spliced into, which is where
    // the numbering has to happen for the keys to come out unique.
    it("numbers the keys a loop repeats", () => {
      // <span>{%for ...}<em></em><div></div>{/for}</span>
      const iteration = () =>
        Type.list([keyedElement("em", 0), keyedElement("div", 1)]);

      const node = element("span", [
        Type.list([iteration(), iteration(), iteration()]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(
        result.children.map((child) => child.key),
        [
          "1a2b3c:0",
          "1a2b3c:1",
          "1a2b3c:0:1",
          "1a2b3c:1:1",
          "1a2b3c:0:2",
          "1a2b3c:1:2",
        ],
      );
    });

    it("with nested stateful components", () => {
      const cid3 = Type.bitstring("component_3");
      const cid7 = Type.bitstring("component_7");

      // <!--<div attr="value"><Module3 /><Module7 /></div>-->
      const node = Type.tuple([
        Type.atom("public_comment"),
        Type.list([
          Type.tuple([
            Type.atom("element"),
            Type.bitstring("div"),
            Type.list([
              Type.tuple([
                Type.bitstring("attr"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("value")],
                ]),
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
                Type.list(),
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
                Type.list(),
              ]),
            ]),
          ]),
        ]),
      ]);

      const entry3 = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module3"),
        state: Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
        ]),
      });

      ComponentRegistry.putEntry(cid3, entry3);

      const entry7 = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module7"),
        state: Type.map([
          [Type.atom("c"), Type.integer(3)],
          [Type.atom("d"), Type.integer(4)],
        ]),
      });

      ComponentRegistry.putEntry(cid7, entry7);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode(
        "!",
        '<div attr="value"><div>state_a = 1, state_b = 2</div><div>state_c = 3, state_d = 4</div></div>',
      );

      assert.deepStrictEqual(result, expected);
    });
  });

  it("DOCTYPE node", () => {
    const node = Type.tuple([Type.atom("doctype"), Type.bitstring("html")]);

    const result = Renderer.renderDom(
      node,
      context,
      slots,
      defaultTarget,
      null,
    );

    assert.deepStrictEqual(result, Type.nil());
  });

  it("expression node", () => {
    const node = Type.tuple([
      Type.atom("expression"),
      Type.tuple([Type.integer(123)]),
    ]);

    const result = Renderer.renderDom(
      node,
      context,
      slots,
      defaultTarget,
      parentTagName,
    );

    assert.equal(result, "123");
  });

  describe("element node", () => {
    it("non-void element, without attributes or children", () => {
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("div"),
        Type.list(),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode("div", {attrs: {}, on: {}}, []);

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
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode(
        "div",
        {attrs: {attr_1: "aaa", attr_2: "123", attr_3: "ccc987eee"}, on: {}},
        [],
      );

      assert.deepStrictEqual(result, expected);
    });

    it("non-void element, with children", () => {
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("div"),
        Type.list(),
        Type.list([
          Type.tuple([
            Type.atom("element"),
            Type.bitstring("span"),
            Type.list(),
            Type.keywordList([[Type.atom("text"), Type.bitstring("abc")]]),
          ]),
          Type.tuple([Type.atom("text"), Type.bitstring("xyz")]),
        ]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode("div", {attrs: {}, on: {}}, [
        vnode("span", {attrs: {}, on: {}}, ["abc"]),
        "xyz",
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("void element, without attributes", () => {
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("img"),
        Type.list(),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode("img", {attrs: {}, on: {}}, []);

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
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode(
        "img",
        {attrs: {attr_1: "aaa", attr_2: "123", attr_3: "ccc987eee"}, on: {}},
        [],
      );

      assert.deepStrictEqual(result, expected);
    });

    it("boolean attributes", () => {
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("img"),
        Type.list([
          Type.tuple([Type.bitstring("attr_1"), Type.keywordList()]),
          Type.tuple([
            Type.bitstring("attr_2"),
            Type.keywordList([[Type.atom("text"), Type.bitstring("")]]),
          ]),
        ]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode(
        "img",
        {attrs: {attr_1: true, attr_2: true}, on: {}},
        [],
      );

      assert.deepStrictEqual(result, expected);
    });

    it("attributes that evaluate to nil are not rendered", () => {
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("img"),
        Type.list([
          Type.tuple([
            Type.bitstring("attr_1"),
            Type.keywordList([
              [Type.atom("expression"), Type.tuple([Type.nil()])],
            ]),
          ]),
          Type.tuple([
            Type.bitstring("attr_2"),
            Type.keywordList([[Type.atom("text"), Type.bitstring("value_2")]]),
          ]),
          Type.tuple([
            Type.bitstring("attr_3"),
            Type.keywordList([
              [Type.atom("expression"), Type.tuple([Type.nil()])],
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode("img", {attrs: {attr_2: "value_2"}, on: {}}, []);

      assert.deepStrictEqual(result, expected);
    });

    it("attributes that evaluate to false are not rendered", () => {
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("img"),
        Type.list([
          Type.tuple([
            Type.bitstring("attr_1"),
            Type.keywordList([
              [Type.atom("expression"), Type.tuple([Type.boolean(false)])],
            ]),
          ]),
          Type.tuple([
            Type.bitstring("attr_2"),
            Type.keywordList([[Type.atom("text"), Type.bitstring("value_2")]]),
          ]),
          Type.tuple([
            Type.bitstring("attr_3"),
            Type.keywordList([
              [Type.atom("expression"), Type.tuple([Type.boolean(false)])],
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode("img", {attrs: {attr_2: "value_2"}, on: {}}, []);

      assert.deepStrictEqual(result, expected);
    });

    // This test case doesn't apply to the client renderer
    // it("if there are no attributes to render there is no whitespace inside the tag, non-void element")

    // This test case doesn't apply to the client renderer
    // it("if there are no attributes to render there is no whitespace inside the tag, void element")

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
          Type.tuple([Type.bitstring("attr_7"), Type.keywordList()]),
          Type.tuple([Type.bitstring("$attr_8"), Type.keywordList()]),
        ]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result.data.attrs, {
        attr_1: "aaa",
        attr_3: "111",
        attr_5: "ccc999ddd",
        attr_7: true,
      });
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
            Type.list(),
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
            Type.list(),
          ]),
        ]),
      ]);

      const entry3 = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module3"),
        state: Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
        ]),
      });

      ComponentRegistry.putEntry(cid3, entry3);

      const entry7 = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module7"),
        state: Type.map([
          [Type.atom("c"), Type.integer(3)],
          [Type.atom("d"), Type.integer(4)],
        ]),
      });

      ComponentRegistry.putEntry(cid7, entry7);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(
        result,
        vnode("div", {attrs: {attr: "value"}, on: {}}, [
          vnode("div", {attrs: {}, on: {}}, ["state_a = 1, state_b = 2"]),
          vnode("div", {attrs: {}, on: {}}, ["state_c = 3, state_d = 4"]),
        ]),
      );

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([
          [cid3, entry3],
          [cid7, entry7],
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

          const vdom = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          assert.deepStrictEqual(Object.keys(vdom.data.on), ["click"]);

          const stub = sinon
            .stub(Hologram, "handleUiEvent")
            .callsFake(
              (_event, _eventType, _operationSpecVdom, _defaultTarget) => null,
            );

          vdom.data.on.click("dummyEvent");

          sinon.assert.calledWith(
            stub,
            "dummyEvent",
            "click",
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
            ]),
            defaultTarget,
          );

          Hologram.handleUiEvent.restore();
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
            Type.list(),
          ]);

          const vdom = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          assert.deepStrictEqual(Object.keys(vdom.data.on), ["click", "focus"]);

          const stub = sinon
            .stub(Hologram, "handleUiEvent")
            .callsFake(
              (_event, _eventType, _operationSpecVdom, _defaultTarget) => null,
            );

          vdom.data.on.click("dummyClickEvent");
          vdom.data.on.focus("dummyFocusEvent");

          sinon.assert.calledWith(
            stub,
            "dummyClickEvent",
            "click",
            Type.list([
              Type.tuple([
                Type.atom("text"),
                Type.bitstring("my_click_action"),
              ]),
            ]),
            defaultTarget,
          );

          sinon.assert.calledWith(
            stub,
            "dummyFocusEvent",
            "focus",
            Type.list([
              Type.tuple([
                Type.atom("text"),
                Type.bitstring("my_focus_action"),
              ]),
            ]),
            defaultTarget,
          );

          Hologram.handleUiEvent.restore();
        });

        it("multiple handlers for the same event name", () => {
          // <input $key_down="my_action_a" $key_down="my_action_b" />
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("$key_down"),
                Type.list([
                  Type.tuple([
                    Type.atom("text"),
                    Type.bitstring("my_action_a"),
                  ]),
                ]),
              ]),
              Type.tuple([
                Type.bitstring("$key_down"),
                Type.list([
                  Type.tuple([
                    Type.atom("text"),
                    Type.bitstring("my_action_b"),
                  ]),
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const vdom = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          assert.deepStrictEqual(Object.keys(vdom.data.on), ["keydown"]);

          const stub = sinon
            .stub(Hologram, "handleUiEvent")
            .callsFake(
              (_event, _eventType, _operationSpecVdom, _defaultTarget) => null,
            );

          vdom.data.on.keydown("dummyEvent");

          sinon.assert.calledTwice(stub);

          sinon.assert.calledWith(
            stub,
            "dummyEvent",
            "keydown",
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("my_action_a")]),
            ]),
            defaultTarget,
          );

          sinon.assert.calledWith(
            stub,
            "dummyEvent",
            "keydown",
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("my_action_b")]),
            ]),
            defaultTarget,
          );

          Hologram.handleUiEvent.restore();
        });

        describe("event name mapping", () => {
          it("maps $mouse_move to mousemove", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("div"),
              Type.list([
                Type.tuple([
                  Type.bitstring("$mouse_move"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const vdom = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              null,
            );

            assert.deepStrictEqual(Object.keys(vdom.data.on), ["mousemove"]);
          });

          it("maps $change event to $input event for text input element", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("input"),
              Type.list([
                Type.tuple([
                  Type.bitstring("type"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("text")],
                  ]),
                ]),
                Type.tuple([
                  Type.bitstring("$change"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const vdom = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            assert.deepStrictEqual(Object.keys(vdom.data.on), ["input"]);

            const stub = sinon
              .stub(Hologram, "handleUiEvent")
              .callsFake((..._args) => null);

            vdom.data.on.input("dummyEvent");

            sinon.assert.calledWith(
              stub,
              "dummyEvent",
              "input",
              Type.list([
                Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
              ]),
              defaultTarget,
            );

            Hologram.handleUiEvent.restore();
          });

          it("keeps $change event for checkbox element", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("input"),
              Type.list([
                Type.tuple([
                  Type.bitstring("type"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("checkbox")],
                  ]),
                ]),
                Type.tuple([
                  Type.bitstring("$change"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const vdom = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            assert.deepStrictEqual(Object.keys(vdom.data.on), ["change"]);

            const stub = sinon
              .stub(Hologram, "handleUiEvent")
              .callsFake((..._args) => null);

            vdom.data.on.change("dummyEvent");

            sinon.assert.calledWith(
              stub,
              "dummyEvent",
              "change",
              Type.list([
                Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
              ]),
              defaultTarget,
            );

            Hologram.handleUiEvent.restore();
          });

          it("maps $change event to $input event for textarea element", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("textarea"),
              Type.list([
                Type.tuple([
                  Type.bitstring("$change"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const vdom = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            assert.deepStrictEqual(Object.keys(vdom.data.on), ["input"]);

            const stub = sinon
              .stub(Hologram, "handleUiEvent")
              .callsFake((..._args) => null);

            vdom.data.on.input("dummyEvent");

            sinon.assert.calledWith(
              stub,
              "dummyEvent",
              "input",
              Type.list([
                Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
              ]),
              defaultTarget,
            );

            Hologram.handleUiEvent.restore();
          });

          it("maps $change event to $input event for input element without type attribute", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("input"),
              Type.list([
                Type.tuple([
                  Type.bitstring("$change"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const vdom = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            assert.deepStrictEqual(Object.keys(vdom.data.on), ["input"]);

            const stub = sinon
              .stub(Hologram, "handleUiEvent")
              .callsFake((..._args) => null);

            vdom.data.on.input("dummyEvent");

            sinon.assert.calledWith(
              stub,
              "dummyEvent",
              "input",
              Type.list([
                Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
              ]),
              defaultTarget,
            );

            Hologram.handleUiEvent.restore();
          });
        });

        describe("allow default", () => {
          const buildNode = (modifiers) =>
            Type.tuple([
              Type.atom("element"),
              Type.bitstring("button"),
              Type.list([
                Type.tuple([
                  Type.bitstring("$click"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                  modifiers,
                ]),
              ]),
              Type.list(),
            ]);

          it("passes allowDefault true when the modifier is present", () => {
            const vdom = Renderer.renderDom(
              buildNode(
                Type.map([[Type.atom("allow_default"), Type.boolean(true)]]),
              ),
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const stub = sinon
              .stub(Hologram, "handleUiEvent")
              .callsFake(() => null);

            vdom.data.on.click("dummyEvent");

            assert.isTrue(stub.getCall(0).args[4]);

            Hologram.handleUiEvent.restore();
          });

          it("passes allowDefault false when the modifier is absent", () => {
            const vdom = Renderer.renderDom(
              buildNode(Type.map()),
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const stub = sinon
              .stub(Hologram, "handleUiEvent")
              .callsFake(() => null);

            vdom.data.on.click("dummyEvent");

            assert.isFalse(stub.getCall(0).args[4]);

            Hologram.handleUiEvent.restore();
          });

          it("composes with a key filter", () => {
            // <input $key_down.enter.allow_default="my_action" />
            const modifiers = Type.map([
              [Type.atom("allow_default"), Type.boolean(true)],
              [
                Type.atom("key"),
                Type.list([Type.list([Type.bitstring("enter")])]),
              ],
            ]);

            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("input"),
              Type.list([
                Type.tuple([
                  Type.bitstring("$key_down"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                  modifiers,
                ]),
              ]),
              Type.list(),
            ]);

            const vdom = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const stub = sinon
              .stub(Hologram, "handleUiEvent")
              .callsFake(() => null);

            // The key filter gates - a non-matching key never reaches handleUiEvent.
            vdom.data.on.keydown({key: "Escape", currentTarget: {}});
            sinon.assert.notCalled(stub);

            // A matching key reaches handleUiEvent synchronously with allowDefault set.
            vdom.data.on.keydown({key: "Enter", currentTarget: {}});
            sinon.assert.calledOnce(stub);
            assert.isTrue(stub.getCall(0).args[4]);

            Hologram.handleUiEvent.restore();
          });
        });

        describe("debounce", () => {
          let clock;

          beforeEach(() => {
            clock = sinon.useFakeTimers();
          });

          afterEach(() => {
            clock.restore();
          });

          it("dispatches once after the window rather than on each event", () => {
            // <button $click.debounce(250)="my_action"></button>
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("button"),
              Type.list([
                Type.tuple([
                  Type.bitstring("$click"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                  Type.map([[Type.atom("debounce"), Type.integer(250)]]),
                ]),
              ]),
              Type.list(),
            ]);

            const vdom = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Each event returns its own dispatch so the trailing edge can be identified.
            const dispatches = [];
            const stub = sinon.stub(Hologram, "handleUiEvent").callsFake(() => {
              const dispatch = sinon.spy();
              dispatches.push(dispatch);
              return dispatch;
            });

            const element = {};
            const firstEvent = {currentTarget: element};
            const lastEvent = {currentTarget: element};

            vdom.data.on.click(firstEvent);
            vdom.data.on.click(lastEvent);

            // handleUiEvent runs synchronously on every event (so preventDefault is never
            // deferred), but no dispatch has fired yet - only the timer is pending.
            sinon.assert.calledTwice(stub);
            assert.strictEqual(stub.getCall(0).args[0], firstEvent);
            assert.strictEqual(stub.getCall(1).args[0], lastEvent);
            sinon.assert.notCalled(dispatches[0]);
            sinon.assert.notCalled(dispatches[1]);

            clock.tick(250);

            // Trailing edge: only the final event's dispatch runs.
            sinon.assert.notCalled(dispatches[0]);
            sinon.assert.calledOnce(dispatches[1]);

            Hologram.handleUiEvent.restore();
          });

          it("composes a key filter with a debounce window", () => {
            // <div $key_down.enter.debounce(200)="my_action"></div>
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("div"),
              Type.list([
                Type.tuple([
                  Type.bitstring("$key_down"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                  Type.map([
                    [Type.atom("debounce"), Type.integer(200)],
                    [
                      Type.atom("key"),
                      Type.list([Type.list([Type.bitstring("enter")])]),
                    ],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const vdom = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            let dispatch;
            sinon.stub(Hologram, "handleUiEvent").callsFake(() => {
              dispatch = sinon.spy();
              return dispatch;
            });

            // A non-matching key is gated out before anything is scheduled.
            vdom.data.on.keydown({key: "Escape", currentTarget: {}});
            sinon.assert.notCalled(Hologram.handleUiEvent);

            // A matching key schedules a debounced dispatch.
            vdom.data.on.keydown({key: "Enter", currentTarget: {}});
            sinon.assert.notCalled(dispatch);

            clock.tick(200);
            sinon.assert.calledOnce(dispatch);

            Hologram.handleUiEvent.restore();
          });

          it("keeps a stable slot across re-renders when action params change", () => {
            // The same binding re-rendered with a different evaluated param must still coalesce -
            // the slot key must not depend on the action spec, only on the static name/modifiers.
            const buildNode = (paramValue) =>
              Type.tuple([
                Type.atom("element"),
                Type.bitstring("button"),
                Type.list([
                  Type.tuple([
                    Type.bitstring("$click"),
                    Type.list([
                      Type.tuple([
                        Type.atom("expression"),
                        Type.tuple([
                          Type.atom("my_action"),
                          Type.keywordList([
                            [Type.atom("n"), Type.integer(paramValue)],
                          ]),
                        ]),
                      ]),
                    ]),
                    Type.map([[Type.atom("debounce"), Type.integer(250)]]),
                  ]),
                ]),
                Type.list(),
              ]);

            const dispatches = [];
            sinon.stub(Hologram, "handleUiEvent").callsFake(() => {
              const dispatch = sinon.spy();
              dispatches.push(dispatch);
              return dispatch;
            });

            const element = {};

            // First render (param 1) schedules a debounce timer for the element.
            const vdom1 = Renderer.renderDom(
              buildNode(1),
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            vdom1.data.on.click({currentTarget: element});

            // A re-render with a changed param must reuse the same slot, so the next event
            // cancels the pending timer instead of scheduling a second one.
            const vdom2 = Renderer.renderDom(
              buildNode(2),
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            vdom2.data.on.click({currentTarget: element});

            clock.tick(250);

            // Both events share one slot, so the second cancels the first's timer -
            // only the later dispatch survives.
            sinon.assert.notCalled(dispatches[0]);
            sinon.assert.calledOnce(dispatches[1]);

            Hologram.handleUiEvent.restore();
          });
        });

        describe("key filters", () => {
          it("fires only on the matching key", () => {
            // <div $key_down.enter="my_action"></div>
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("div"),
              Type.list([
                Type.tuple([
                  Type.bitstring("$key_down"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                  Type.map([
                    [
                      Type.atom("key"),
                      Type.list([Type.list([Type.bitstring("enter")])]),
                    ],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const vdom = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const stub = sinon
              .stub(Hologram, "handleUiEvent")
              .callsFake(
                (_event, _eventType, _operationSpecVdom, _defaultTarget) =>
                  null,
              );

            // A non-matching key is gated out - the handler never dispatches.
            vdom.data.on.keydown({key: "Escape"});
            sinon.assert.notCalled(stub);

            vdom.data.on.keydown({key: "Enter"});
            sinon.assert.calledOnce(stub);

            sinon.assert.calledWith(
              stub,
              {key: "Enter"},
              "keydown",
              Type.list([
                Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
              ]),
              defaultTarget,
            );

            Hologram.handleUiEvent.restore();
          });

          it("grouped bindings each fire only on their own key", () => {
            // <div $key_down.enter="my_enter_action" $key_down.escape="my_escape_action"></div>
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("div"),
              Type.list([
                Type.tuple([
                  Type.bitstring("$key_down"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_enter_action"),
                    ]),
                  ]),
                  Type.map([
                    [
                      Type.atom("key"),
                      Type.list([Type.list([Type.bitstring("enter")])]),
                    ],
                  ]),
                ]),
                Type.tuple([
                  Type.bitstring("$key_down"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_escape_action"),
                    ]),
                  ]),
                  Type.map([
                    [
                      Type.atom("key"),
                      Type.list([Type.list([Type.bitstring("escape")])]),
                    ],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const vdom = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const stub = sinon
              .stub(Hologram, "handleUiEvent")
              .callsFake(
                (_event, _eventType, _operationSpecVdom, _defaultTarget) =>
                  null,
              );

            vdom.data.on.keydown({key: "Enter"});
            sinon.assert.calledOnce(stub);

            sinon.assert.calledWith(
              stub,
              {key: "Enter"},
              "keydown",
              Type.list([
                Type.tuple([
                  Type.atom("text"),
                  Type.bitstring("my_enter_action"),
                ]),
              ]),
              defaultTarget,
            );

            stub.resetHistory();

            vdom.data.on.keydown({key: "Escape"});
            sinon.assert.calledOnce(stub);

            sinon.assert.calledWith(
              stub,
              {key: "Escape"},
              "keydown",
              Type.list([
                Type.tuple([
                  Type.atom("text"),
                  Type.bitstring("my_escape_action"),
                ]),
              ]),
              defaultTarget,
            );

            Hologram.handleUiEvent.restore();
          });
        });

        describe("once", () => {
          let clock;

          beforeEach(() => {
            clock = sinon.useFakeTimers();
          });

          afterEach(() => {
            clock.restore();
          });

          const buildNode = (modifiers) =>
            Type.tuple([
              Type.atom("element"),
              Type.bitstring("button"),
              Type.list([
                Type.tuple([
                  Type.bitstring("$click"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                  modifiers,
                ]),
              ]),
              Type.list(),
            ]);

          it("dispatches the action only on the first event, then stops", () => {
            const vdom = Renderer.renderDom(
              buildNode(Type.map([[Type.atom("once"), Type.boolean(true)]])),
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const dispatches = [];
            const stub = sinon.stub(Hologram, "handleUiEvent").callsFake(() => {
              const dispatch = sinon.spy();
              dispatches.push(dispatch);
              return dispatch;
            });

            const element = {};

            vdom.data.on.click({currentTarget: element});
            vdom.data.on.click({currentTarget: element});

            // handleUiEvent runs on both events, so a spent binding still applies preventDefault /
            // stop_propagation - only the re-dispatch is suppressed.
            sinon.assert.calledTwice(stub);
            sinon.assert.calledOnce(dispatches[0]);
            sinon.assert.notCalled(dispatches[1]);

            Hologram.handleUiEvent.restore();
          });

          it("stays armed when the first event's dispatch is ignored", () => {
            const vdom = Renderer.renderDom(
              buildNode(Type.map([[Type.atom("once"), Type.boolean(true)]])),
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const dispatch = sinon.spy();
            const stub = sinon.stub(Hologram, "handleUiEvent");
            stub.onCall(0).returns(null);
            stub.onCall(1).returns(dispatch);

            const element = {};

            // The first event is ignored (null dispatch), so once is not consumed.
            vdom.data.on.click({currentTarget: element});
            // The second event dispatches and spends the binding.
            vdom.data.on.click({currentTarget: element});

            sinon.assert.calledOnce(dispatch);

            Hologram.handleUiEvent.restore();
          });

          it("fires once on the trailing edge when composed with debounce", () => {
            const vdom = Renderer.renderDom(
              buildNode(
                Type.map([
                  [Type.atom("debounce"), Type.integer(250)],
                  [Type.atom("once"), Type.boolean(true)],
                ]),
              ),
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const dispatches = [];
            sinon.stub(Hologram, "handleUiEvent").callsFake(() => {
              const dispatch = sinon.spy();
              dispatches.push(dispatch);
              return dispatch;
            });

            const element = {};

            vdom.data.on.click({currentTarget: element});
            vdom.data.on.click({currentTarget: element});
            clock.tick(250);

            // Trailing edge: only the last event in the burst dispatches.
            sinon.assert.notCalled(dispatches[0]);
            sinon.assert.calledOnce(dispatches[1]);

            // A later event finds the binding spent, so nothing further is scheduled or dispatched.
            vdom.data.on.click({currentTarget: element});
            clock.tick(250);
            assert.strictEqual(dispatches.length, 3);
            sinon.assert.notCalled(dispatches[2]);

            Hologram.handleUiEvent.restore();
          });

          it("fires once on the leading edge when composed with throttle", () => {
            const vdom = Renderer.renderDom(
              buildNode(
                Type.map([
                  [Type.atom("once"), Type.boolean(true)],
                  [Type.atom("throttle"), Type.integer(100)],
                ]),
              ),
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const dispatches = [];
            sinon.stub(Hologram, "handleUiEvent").callsFake(() => {
              const dispatch = sinon.spy();
              dispatches.push(dispatch);
              return dispatch;
            });

            const element = {};

            // Leading edge dispatches and spends the binding.
            vdom.data.on.click({currentTarget: element});
            sinon.assert.calledOnce(dispatches[0]);

            // A second event within the window finds the binding spent, so nothing is held.
            vdom.data.on.click({currentTarget: element});
            sinon.assert.notCalled(dispatches[1]);

            // The window closes with nothing held, so the trailing edge never fires.
            clock.tick(100);
            sinon.assert.calledOnce(dispatches[0]);
            sinon.assert.notCalled(dispatches[1]);

            Hologram.handleUiEvent.restore();
          });
        });

        describe("prevent default", () => {
          const buildNode = (modifiers) =>
            Type.tuple([
              Type.atom("element"),
              Type.bitstring("button"),
              Type.list([
                Type.tuple([
                  Type.bitstring("$click"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                  modifiers,
                ]),
              ]),
              Type.list(),
            ]);

          it("passes forcePreventDefault true when the modifier is present", () => {
            const vdom = Renderer.renderDom(
              buildNode(
                Type.map([[Type.atom("prevent_default"), Type.boolean(true)]]),
              ),
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const stub = sinon
              .stub(Hologram, "handleUiEvent")
              .callsFake(() => null);

            vdom.data.on.click("dummyEvent");

            assert.isTrue(stub.getCall(0).args[6]);

            Hologram.handleUiEvent.restore();
          });

          it("passes forcePreventDefault false when the modifier is absent", () => {
            const vdom = Renderer.renderDom(
              buildNode(Type.map()),
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const stub = sinon
              .stub(Hologram, "handleUiEvent")
              .callsFake(() => null);

            vdom.data.on.click("dummyEvent");

            assert.isFalse(stub.getCall(0).args[6]);

            Hologram.handleUiEvent.restore();
          });

          it("composes with a key filter", () => {
            // <input $key_down.enter.prevent_default="my_action" />
            const modifiers = Type.map([
              [
                Type.atom("key"),
                Type.list([Type.list([Type.bitstring("enter")])]),
              ],
              [Type.atom("prevent_default"), Type.boolean(true)],
            ]);

            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("input"),
              Type.list([
                Type.tuple([
                  Type.bitstring("$key_down"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                  modifiers,
                ]),
              ]),
              Type.list(),
            ]);

            const vdom = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const stub = sinon
              .stub(Hologram, "handleUiEvent")
              .callsFake(() => null);

            // The key filter gates - a non-matching key never reaches handleUiEvent.
            vdom.data.on.keydown({key: "Escape", currentTarget: {}});
            sinon.assert.notCalled(stub);

            // A matching key reaches handleUiEvent synchronously with forcePreventDefault set.
            vdom.data.on.keydown({key: "Enter", currentTarget: {}});
            sinon.assert.calledOnce(stub);
            assert.isTrue(stub.getCall(0).args[6]);

            Hologram.handleUiEvent.restore();
          });
        });

        describe("stop propagation", () => {
          const buildNode = (modifiers) =>
            Type.tuple([
              Type.atom("element"),
              Type.bitstring("button"),
              Type.list([
                Type.tuple([
                  Type.bitstring("$click"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                  modifiers,
                ]),
              ]),
              Type.list(),
            ]);

          it("passes stopPropagation true when the modifier is present", () => {
            const vdom = Renderer.renderDom(
              buildNode(
                Type.map([[Type.atom("stop_propagation"), Type.boolean(true)]]),
              ),
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const stub = sinon
              .stub(Hologram, "handleUiEvent")
              .callsFake(() => null);

            vdom.data.on.click("dummyEvent");

            assert.isTrue(stub.getCall(0).args[5]);

            Hologram.handleUiEvent.restore();
          });

          it("passes stopPropagation false when the modifier is absent", () => {
            const vdom = Renderer.renderDom(
              buildNode(Type.map()),
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const stub = sinon
              .stub(Hologram, "handleUiEvent")
              .callsFake(() => null);

            vdom.data.on.click("dummyEvent");

            assert.isFalse(stub.getCall(0).args[5]);

            Hologram.handleUiEvent.restore();
          });

          it("composes with a key filter and allow_default", () => {
            // <input $key_down.enter.allow_default.stop_propagation="my_action" />
            const modifiers = Type.map([
              [Type.atom("allow_default"), Type.boolean(true)],
              [
                Type.atom("key"),
                Type.list([Type.list([Type.bitstring("enter")])]),
              ],
              [Type.atom("stop_propagation"), Type.boolean(true)],
            ]);

            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("input"),
              Type.list([
                Type.tuple([
                  Type.bitstring("$key_down"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                  modifiers,
                ]),
              ]),
              Type.list(),
            ]);

            const vdom = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const stub = sinon
              .stub(Hologram, "handleUiEvent")
              .callsFake(() => null);

            // The key filter gates - a non-matching key never reaches handleUiEvent.
            vdom.data.on.keydown({key: "Escape", currentTarget: {}});
            sinon.assert.notCalled(stub);

            // A matching key reaches handleUiEvent synchronously with both flags set.
            vdom.data.on.keydown({key: "Enter", currentTarget: {}});
            sinon.assert.calledOnce(stub);
            assert.isTrue(stub.getCall(0).args[4]);
            assert.isTrue(stub.getCall(0).args[5]);

            Hologram.handleUiEvent.restore();
          });
        });

        describe("throttle", () => {
          let clock;

          beforeEach(() => {
            clock = sinon.useFakeTimers();
          });

          afterEach(() => {
            clock.restore();
          });

          it("dispatches on the leading edge and again on the trailing edge", () => {
            // <button $click.throttle(100)="my_action"></button>
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("button"),
              Type.list([
                Type.tuple([
                  Type.bitstring("$click"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                  Type.map([[Type.atom("throttle"), Type.integer(100)]]),
                ]),
              ]),
              Type.list(),
            ]);

            const vdom = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const dispatches = [];
            const stub = sinon.stub(Hologram, "handleUiEvent").callsFake(() => {
              const dispatch = sinon.spy();
              dispatches.push(dispatch);
              return dispatch;
            });

            const element = {};
            const firstEvent = {currentTarget: element};
            const lastEvent = {currentTarget: element};

            vdom.data.on.click(firstEvent);
            vdom.data.on.click(lastEvent);

            // handleUiEvent runs synchronously on every event. The first dispatches immediately
            // (leading edge); the second is held.
            sinon.assert.calledTwice(stub);
            sinon.assert.calledOnce(dispatches[0]);
            sinon.assert.notCalled(dispatches[1]);

            clock.tick(100);

            // Trailing edge: the latest held event dispatches.
            sinon.assert.calledOnce(dispatches[0]);
            sinon.assert.calledOnce(dispatches[1]);

            Hologram.handleUiEvent.restore();
          });

          it("composes a key filter with a throttle window", () => {
            // <div $key_down.enter.throttle(100)="my_action"></div>
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("div"),
              Type.list([
                Type.tuple([
                  Type.bitstring("$key_down"),
                  Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("my_action"),
                    ]),
                  ]),
                  Type.map([
                    [
                      Type.atom("key"),
                      Type.list([Type.list([Type.bitstring("enter")])]),
                    ],
                    [Type.atom("throttle"), Type.integer(100)],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const vdom = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            const dispatches = [];
            sinon.stub(Hologram, "handleUiEvent").callsFake(() => {
              const dispatch = sinon.spy();
              dispatches.push(dispatch);
              return dispatch;
            });

            const element = {};

            // A non-matching key is gated out before anything is scheduled.
            vdom.data.on.keydown({key: "Escape", currentTarget: element});
            sinon.assert.notCalled(Hologram.handleUiEvent);

            // Matching keys are throttled: the first dispatches on the leading edge, a second is
            // held and dispatches on the trailing edge.
            vdom.data.on.keydown({key: "Enter", currentTarget: element});
            vdom.data.on.keydown({key: "Enter", currentTarget: element});
            sinon.assert.calledOnce(dispatches[0]);
            sinon.assert.notCalled(dispatches[1]);

            clock.tick(100);
            sinon.assert.calledOnce(dispatches[1]);

            Hologram.handleUiEvent.restore();
          });
        });
      });

      describe("default operation target", () => {
        it("current stateful component", () => {
          const node = Type.tuple([
            Type.atom("component"),
            Type.atom(
              "Elixir.Hologram.Test.Fixtures.Template.Renderer.Module55",
            ),
            Type.list([
              Type.tuple([
                Type.bitstring("cid"),
                Type.list([Type.tuple([Type.atom("text"), cid])]),
              ]),
            ]),
            Type.list(),
          ]);

          initComponentRegistryEntry(
            cid,
            Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module55"),
          );

          const vdom = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          const stub = sinon
            .stub(Hologram, "handleUiEvent")
            .callsFake(
              (_event, _eventType, _operationSpecVdom, _defaultTarget) => null,
            );

          vdom[0].children[1].data.on.click("dummyEvent");

          sinon.assert.calledWith(
            stub,
            "dummyEvent",
            "click",
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
            ]),
            cid,
          );

          Hologram.handleUiEvent.restore();
        });

        it("parent stateful component", () => {
          const node = Type.tuple([
            Type.atom("component"),
            Type.atom(
              "Elixir.Hologram.Test.Fixtures.Template.Renderer.Module55",
            ),
            Type.list(),
            Type.list(),
          ]);

          const vdom = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          const stub = sinon
            .stub(Hologram, "handleUiEvent")
            .callsFake(
              (_event, _eventType, _operationSpecVdom, _defaultTarget) => null,
            );

          vdom[0].children[1].data.on.click("dummyEvent");

          sinon.assert.calledWith(
            stub,
            "dummyEvent",
            "click",
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
            ]),
            defaultTarget,
          );

          Hologram.handleUiEvent.restore();
        });

        it("page", () => {
          initComponentRegistryEntry(
            Type.bitstring("page"),
            Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module56"),
          );
          initComponentRegistryEntry(
            Type.bitstring("layout"),
            Type.alias("Hologram.Test.Fixtures.LayoutFixture"),
          );

          const vdom = Renderer.renderPage(
            Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module56"),
            Type.map(),
          );

          const stub = sinon
            .stub(Hologram, "handleUiEvent")
            .callsFake(
              (_event, _eventType, _operationSpecVdom, _defaultTarget) => null,
            );

          vdom.children[0].children[0].children[1].data.on.click("dummyEvent");

          sinon.assert.calledWith(
            stub,
            "dummyEvent",
            "click",
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
            ]),
            Type.bitstring("page"),
          );

          Hologram.handleUiEvent.restore();
        });

        it("layout", () => {
          initComponentRegistryEntry(
            Type.bitstring("page"),
            Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module57"),
          );
          initComponentRegistryEntry(
            Type.bitstring("layout"),
            Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module58"),
          );

          const vdom = Renderer.renderPage(
            Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module57"),
            Type.map(),
          );

          const stub = sinon
            .stub(Hologram, "handleUiEvent")
            .callsFake(
              (_event, _eventType, _operationSpecVdom, _defaultTarget) => null,
            );

          vdom.children[0].children[0].children[1].data.on.click("dummyEvent");

          sinon.assert.calledOnce(stub);
          const call = stub.getCall(0);

          assert.equal(call.args[0], "dummyEvent");
          assert.equal(call.args[1], "click");
          assert.isTrue(Type.isList(call.args[2]));
          assert.equal(call.args[2].data.length, 1);
          assert.isTrue(Type.isTuple(call.args[2].data[0]));
          assert.equal(call.args[2].data[0].data.length, 2);

          assert.deepStrictEqual(
            call.args[2].data[0].data[0],
            Type.atom("text"),
          );

          assert.isTrue(
            Interpreter.isStrictlyEqual(
              call.args[2].data[0].data[1],
              Type.bitstring("my_action"),
            ),
          );

          assert.isTrue(
            Interpreter.isStrictlyEqual(call.args[3], Type.bitstring("layout")),
          );

          Hologram.handleUiEvent.restore();
        });

        it("slot of a stateful component nested in another stateful component", () => {
          const node = Type.tuple([
            Type.atom("component"),
            Type.atom(
              "Elixir.Hologram.Test.Fixtures.Template.Renderer.Module59",
            ),
            Type.list([
              Type.tuple([
                Type.bitstring("cid"),
                Type.list([
                  Type.tuple([
                    Type.atom("text"),
                    Type.bitstring("component_59"),
                  ]),
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          initComponentRegistryEntry(
            Type.bitstring("component_59"),
            Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module59"),
          );
          initComponentRegistryEntry(
            Type.bitstring("component_60"),
            Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module60"),
          );
          initComponentRegistryEntry(
            Type.bitstring("component_61"),
            Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module61"),
          );

          const vdom = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          const stub = sinon
            .stub(Hologram, "handleUiEvent")
            .callsFake(
              (_event, _eventType, _operationSpecVdom, _defaultTarget) => null,
            );

          vdom[0].children[1].children[1].data.on.click("dummyEvent");

          sinon.assert.calledOnce(stub);
          const call = stub.getCall(0);

          assert.equal(call.args[0], "dummyEvent");
          assert.equal(call.args[1], "click");
          assert.isTrue(Type.isList(call.args[2]));
          assert.equal(call.args[2].data.length, 1);
          assert.isTrue(Type.isTuple(call.args[2].data[0]));
          assert.equal(call.args[2].data[0].data.length, 2);

          assert.deepStrictEqual(
            call.args[2].data[0].data[0],
            Type.atom("text"),
          );

          assert.isTrue(
            Interpreter.isStrictlyEqual(
              call.args[2].data[0].data[1],
              Type.bitstring("my_action"),
            ),
          );

          assert.isTrue(
            Interpreter.isStrictlyEqual(
              call.args[3],
              Type.bitstring("component_61"),
            ),
          );

          Hologram.handleUiEvent.restore();
        });
      });

      describe("link element vnode key", () => {
        it("not a link element", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("a"),
            Type.list([
              Type.tuple([
                Type.bitstring("href"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("my_href")],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          const expected = vnode("a", {attrs: {href: "my_href"}, on: {}}, []);

          assert.deepStrictEqual(result, expected);
        });

        it("link element without href attribute", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("link"),
            Type.list([
              Type.tuple([
                Type.bitstring("rel"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("stylesheet")],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          const expected = vnode(
            "link",
            {attrs: {rel: "stylesheet"}, on: {}},
            [],
          );

          assert.deepStrictEqual(result, expected);
        });

        it("link element with empty string href attribute", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("link"),
            Type.list([
              Type.tuple([
                Type.bitstring("href"),
                Type.keywordList([[Type.atom("text"), Type.bitstring("")]]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          const expected = vnode("link", {attrs: {href: true}, on: {}}, []);

          assert.deepStrictEqual(result, expected);
        });

        it("link element with boolean href attribute", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("link"),
            Type.list([
              Type.tuple([Type.bitstring("href"), Type.keywordList()]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          const expected = vnode("link", {attrs: {href: true}, on: {}}, []);

          assert.deepStrictEqual(result, expected);
        });

        it("link element with non-empty href attribute", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("link"),
            Type.list([
              Type.tuple([
                Type.bitstring("href"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("my_href")],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          const expected = vnode(
            "link",
            {
              key: "__hologramLink__:my_href",
              attrs: {href: "my_href"},
              on: {},
            },
            [],
          );

          assert.deepStrictEqual(result, expected);
        });
      });

      describe("script element vnode key", () => {
        it("not a script element", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("img"),
            Type.list([
              Type.tuple([
                Type.bitstring("src"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("my_src")],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          const expected = vnode("img", {attrs: {src: "my_src"}, on: {}}, []);

          assert.deepStrictEqual(result, expected);
        });

        it("script element without src attribute (inline script)", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("script"),
            Type.list([
              Type.tuple([
                Type.bitstring("type"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("text/javascript")],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          const expected = vnode(
            "script",
            {attrs: {type: "text/javascript"}, on: {}},
            [],
          );

          assert.deepStrictEqual(result, expected);
        });

        it("script element with empty string src attribute", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("script"),
            Type.list([
              Type.tuple([
                Type.bitstring("src"),
                Type.keywordList([[Type.atom("text"), Type.bitstring("")]]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          const expected = vnode("script", {attrs: {src: true}, on: {}}, []);

          assert.deepStrictEqual(result, expected);
        });

        it("script element with boolean src attribute", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("script"),
            Type.list([
              Type.tuple([Type.bitstring("src"), Type.keywordList()]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          const expected = vnode("script", {attrs: {src: true}, on: {}}, []);

          assert.deepStrictEqual(result, expected);
        });

        it("script element with non-empty src attribute", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("script"),
            Type.list([
              Type.tuple([
                Type.bitstring("src"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("my_src")],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          const expected = vnode(
            "script",
            {
              key: "__hologramScript__:my_src",
              attrs: {src: "my_src"},
              on: {},
            },
            [],
          );

          assert.deepStrictEqual(result, expected);
        });

        it("script element with non-empty text content", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("script"),
            Type.list(),
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("const x = 123;")]),
            ]),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          const expected = vnode(
            "script",
            {
              key: "__hologramScript__:const x = 123;",
              attrs: {},
              on: {},
            },
            ["const x = 123;"],
          );

          assert.deepStrictEqual(result, expected);
        });

        it("script element with empty text content", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("script"),
            Type.list(),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          const expected = vnode("script", {attrs: {}, on: {}}, []);

          assert.deepStrictEqual(result, expected);
        });
      });

      describe("slot key", () => {
        const keyAttr = (value) =>
          Type.tuple([
            Type.bitstring("$key"),
            Type.keywordList([[Type.atom("text"), Type.bitstring(value)]]),
          ]);

        const elementWithKey = (tagName, attrs) =>
          Type.tuple([
            Type.atom("element"),
            Type.bitstring(tagName),
            Type.list(attrs),
            Type.list(),
          ]);

        const render = (node) =>
          Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

        it("becomes the vnode key and never an attribute", () => {
          const result = render(elementWithKey("div", [keyAttr("t7:4")]));

          assert.deepStrictEqual(
            result,
            vnode("div", {key: "t7:4", attrs: {}, on: {}}, []),
          );
        });

        it("binds no event listener", () => {
          const result = render(elementWithKey("div", [keyAttr("t7:4")]));

          assert.deepStrictEqual(result.data.on, {});
        });

        it("element without a key carries none", () => {
          const result = render(elementWithKey("div", []));

          assert.isUndefined(result.key);
        });

        // What an element loads names it better than where it sits, so a stylesheet keeps its
        // href key and does not get re-fetched for having moved in the template.
        it("does not displace a link element's resource key", () => {
          const node = elementWithKey("link", [
            Type.tuple([
              Type.bitstring("href"),
              Type.keywordList([
                [Type.atom("text"), Type.bitstring("my_href")],
              ]),
            ]),
            keyAttr("t7:4"),
          ]);

          assert.equal(render(node).key, "__hologramLink__:my_href");
        });

        it("does not displace a script element's resource key", () => {
          const node = elementWithKey("script", [
            Type.tuple([
              Type.bitstring("src"),
              Type.keywordList([[Type.atom("text"), Type.bitstring("my_src")]]),
            ]),
            keyAttr("t7:4"),
          ]);

          assert.equal(render(node).key, "__hologramScript__:my_src");
        });

        // An inline script is keyed by its own code, and the live node is keyed by its
        // textContent, so the two agree only while the whole body renders as one child. Everything
        // a script can hold renders to text and adjacent text is merged, which is what makes that
        // true - if it stopped being true, the boot patch would rebuild every inline script and
        // the page would re-run its own code.
        it("keys an inline script by the whole of its body", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("script"),
            Type.list(),
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("let x = ")]),
              Type.tuple([
                Type.atom("expression"),
                Type.tuple([Type.integer(123)]),
              ]),
              Type.tuple([Type.atom("text"), Type.bitstring("; go();")]),
            ]),
          ]);

          const result = render(node);

          assert.equal(result.children.length, 1);
          assert.equal(result.children[0].text, "let x = 123; go();");
          assert.equal(result.key, "__hologramScript__:let x = 123; go();");
        });

        // The key is found without expanding the spread, so a tag carrying one has to keep
        // reaching its key.
        it("is found on a tag that also carries a spread", () => {
          const node = elementWithKey("div", [
            Type.tuple([
              Type.atom("spread"),
              Type.tuple([
                Type.map([
                  [Type.bitstring("class"), Type.bitstring("my_class")],
                ]),
              ]),
            ]),
            keyAttr("t7:4"),
          ]);

          assert.equal(render(node).key, "t7:4");
        });

        it("a spread on its own carries no key", () => {
          const node = elementWithKey("div", [
            Type.tuple([
              Type.atom("spread"),
              Type.tuple([
                Type.map([
                  [Type.bitstring("class"), Type.bitstring("my_class")],
                ]),
              ]),
            ]),
          ]);

          assert.isUndefined(render(node).key);
        });
      });

      describe("input element value handling", () => {
        it("text input element with value attribute sets up hooks", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("value"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("test_value")],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should not have the value as an attribute
          assert.isUndefined(result.data.attrs.value);

          // Should not have the temporary data-hologram-form-value attribute
          assert.isUndefined(
            result.data.attrs["data-hologram-form-input-value"],
          );

          // Should have hooks for handling the value property
          assert.strictEqual(typeof result.data.hook, "object");
          assert.strictEqual(typeof result.data.hook.create, "function");
          assert.strictEqual(typeof result.data.hook.update, "function");
        });

        it("non-text (but text-based) input element with value attribute sets up hooks", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("type"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("email")],
                ]),
              ]),
              Type.tuple([
                Type.bitstring("value"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("test@example.com")],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should not have the value as an attribute (controlled)
          assert.isUndefined(result.data.attrs.value);

          // Should have the type attribute as a regular attribute
          assert.strictEqual(result.data.attrs.type, "email");

          // Should have hooks for handling the value property
          assert.strictEqual(typeof result.data.hook, "object");
          assert.strictEqual(typeof result.data.hook.create, "function");
          assert.strictEqual(typeof result.data.hook.update, "function");
        });

        it("input element without value attribute does not set up value hooks", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("type"),
                Type.keywordList([[Type.atom("text"), Type.bitstring("text")]]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should have the type attribute
          assert.strictEqual(result.data.attrs.type, "text");

          // Should not have hooks since there's no value attribute
          assert.isUndefined(result.data.hook);
        });

        it("non-input element with value attribute treats value as regular attribute", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("div"),
            Type.list([
              Type.tuple([
                Type.bitstring("value"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("test_value")],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should have the value as a normal attribute for non-input elements
          assert.strictEqual(result.data.attrs.value, "test_value");

          // Should not have hooks since it's not an input
          assert.isUndefined(result.data.hook);
        });

        it("input element with empty string value attribute preserves empty string", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("value"),
                Type.keywordList([[Type.atom("text"), Type.bitstring("")]]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should not have the value as an attribute
          assert.isUndefined(result.data.attrs.value);

          // Should not have the temporary data-hologram-form-value attribute (it gets removed after creating hooks)
          assert.isUndefined(
            result.data.attrs["data-hologram-form-input-value"],
          );

          // Should have hooks for handling the value property (empty string is still a valid value)
          assert.strictEqual(typeof result.data.hook, "object");
          assert.strictEqual(typeof result.data.hook.create, "function");
          assert.strictEqual(typeof result.data.hook.update, "function");
        });

        // nil or false value or attribute not present
        it("input element with undefined value does not set up hooks", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("value"),
                Type.keywordList([
                  [Type.atom("expression"), Type.tuple([Type.nil()])],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should not have the value as an attribute
          assert.isUndefined(result.data.attrs.value);

          // Should not have the temporary data-hologram-form-value attribute
          assert.isUndefined(
            result.data.attrs["data-hologram-form-input-value"],
          );

          // Should not have hooks
          assert.isUndefined(result.data.hook);
        });

        describe("input value handling during updates", () => {
          let mockInput;

          beforeEach(() => {
            mockInput = {
              tagName: "INPUT",
              value: "",
            };
          });

          it("sets initial value on create hook", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("input"),
              Type.list([
                Type.tuple([
                  Type.bitstring("value"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("initial_value")],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Call the create hook with mock vnode
            const mockVnode = {elm: mockInput};
            result.data.hook.create(null, mockVnode);

            // Should set the value
            assert.strictEqual(mockInput.value, "initial_value");
          });

          it("always updates value on update hook", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("input"),
              Type.list([
                Type.tuple([
                  Type.bitstring("value"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("new_value")],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Simulate that we previously set a value
            mockInput.value = "old_value";

            // Call the update hook
            const mockVnode = {
              elm: mockInput,
              data: {hologramFormInputValue: "new_value"},
            };
            result.data.hook.update(null, mockVnode);

            // Should always update the value
            assert.strictEqual(mockInput.value, "new_value");
          });

          it("always overrides user input when value changes", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("input"),
              Type.list([
                Type.tuple([
                  Type.bitstring("value"),
                  Type.keywordList([
                    [
                      Type.atom("text"),
                      Type.bitstring("new_programmatic_value"),
                    ],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Simulate that user has typed something different
            mockInput.value = "user_typed_text";

            // Call the update hook with a new programmatic value
            const mockVnode = {
              elm: mockInput,
              data: {hologramFormInputValue: "new_programmatic_value"},
            };
            result.data.hook.update(null, mockVnode);

            // Should always update the value
            assert.strictEqual(mockInput.value, "new_programmatic_value");
          });

          it("updates value regardless of current input value", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("input"),
              Type.list([
                Type.tuple([
                  Type.bitstring("value"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("new_value")],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Simulate that current value is something else
            mockInput.value = "current_value";

            // Call the update hook
            const mockVnode = {
              elm: mockInput,
              data: {hologramFormInputValue: "new_value"},
            };
            result.data.hook.update(null, mockVnode);

            // Should always update the value
            assert.strictEqual(mockInput.value, "new_value");
          });

          it("sets value on any input element", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("input"),
              Type.list([
                Type.tuple([
                  Type.bitstring("value"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("first_value")],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Simulate input with any current value
            mockInput.value = "whatever";

            // Call the update hook
            const mockVnode = {
              elm: mockInput,
              data: {hologramFormInputValue: "first_value"},
            };
            result.data.hook.update(null, mockVnode);

            // Should always update the value
            assert.strictEqual(mockInput.value, "first_value");
          });

          it("does not update value when it hasn't changed", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("input"),
              Type.list([
                Type.tuple([
                  Type.bitstring("value"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("same_value")],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Set input to the same value as what will be set
            mockInput.value = "same_value";

            // Spy on the value setter to verify it's not called
            let setterCallCount = 0;
            const originalValue = mockInput.value;
            Object.defineProperty(mockInput, "value", {
              get: () => originalValue,
              set: () => {
                setterCallCount++;
              },
              configurable: true,
            });

            // Call the update hook with same value (to test no change)
            const oldVnode = {data: {hologramFormInputValue: "same_value"}};
            const mockVnode = {
              elm: mockInput,
              data: {hologramFormInputValue: "same_value"},
            };
            result.data.hook.update(oldVnode, mockVnode);

            // Should not have called the setter since value didn't change
            assert.strictEqual(setterCallCount, 0);
          });
        });
      });

      describe("textarea value handling", () => {
        it("textarea element with value attribute sets up hooks", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("textarea"),
            Type.list([
              Type.tuple([
                Type.bitstring("value"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("test_value")],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should not have the value as an attribute
          assert.isUndefined(result.data.attrs.value);

          // Should not have the temporary data-hologram-form-value attribute
          assert.isUndefined(
            result.data.attrs["data-hologram-form-input-value"],
          );

          // Should have hooks for handling the value property
          assert.strictEqual(typeof result.data.hook, "object");
          assert.strictEqual(typeof result.data.hook.create, "function");
          assert.strictEqual(typeof result.data.hook.update, "function");
        });

        it("textarea element without value attribute does not set up value hooks", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("textarea"),
            Type.list([
              Type.tuple([
                Type.bitstring("rows"),
                Type.keywordList([[Type.atom("text"), Type.bitstring("10")]]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should have the rows attribute
          assert.strictEqual(result.data.attrs.rows, "10");

          // Should not have hooks since there's no value attribute
          assert.isUndefined(result.data.hook);
        });

        it("non-textarea element with value attribute treats value as regular attribute", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("div"),
            Type.list([
              Type.tuple([
                Type.bitstring("value"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("test_value")],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should have the value as a normal attribute for non-textarea elements
          assert.strictEqual(result.data.attrs.value, "test_value");

          // Should not have hooks since it's not a textarea
          assert.isUndefined(result.data.hook);
        });

        it("textarea element with empty string value attribute preserves empty string", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("textarea"),
            Type.list([
              Type.tuple([
                Type.bitstring("value"),
                Type.keywordList([[Type.atom("text"), Type.bitstring("")]]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should not have the value as an attribute
          assert.isUndefined(result.data.attrs.value);

          // Should not have the temporary data-hologram-form-value attribute (it gets removed after creating hooks)
          assert.isUndefined(
            result.data.attrs["data-hologram-form-input-value"],
          );

          // Should have hooks for handling the value property (empty string is still a valid value)
          assert.strictEqual(typeof result.data.hook, "object");
          assert.strictEqual(typeof result.data.hook.create, "function");
          assert.strictEqual(typeof result.data.hook.update, "function");
        });

        // nil or false value or attribute not present
        it("textarea element with undefined value does not set up hooks", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("textarea"),
            Type.list([
              Type.tuple([
                Type.bitstring("value"),
                Type.keywordList([
                  [Type.atom("expression"), Type.tuple([Type.nil()])],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should not have the value as an attribute
          assert.isUndefined(result.data.attrs.value);

          // Should not have the temporary data-hologram-form-value attribute
          assert.isUndefined(
            result.data.attrs["data-hologram-form-input-value"],
          );

          // Should not have hooks
          assert.isUndefined(result.data.hook);
        });

        describe("textarea value handling during updates", () => {
          let mockTextarea;

          beforeEach(() => {
            mockTextarea = {
              tagName: "TEXTAREA",
              value: "",
            };
          });

          it("sets initial value on create hook", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("textarea"),
              Type.list([
                Type.tuple([
                  Type.bitstring("value"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("initial_value")],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Call the create hook with mock vnode
            const mockVnode = {elm: mockTextarea};
            result.data.hook.create(null, mockVnode);

            // Should set the value
            assert.strictEqual(mockTextarea.value, "initial_value");
          });

          it("always updates value on update hook", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("textarea"),
              Type.list([
                Type.tuple([
                  Type.bitstring("value"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("new_value")],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Simulate that we previously set a value
            mockTextarea.value = "old_value";

            // Call the update hook
            const mockVnode = {
              elm: mockTextarea,
              data: {hologramFormInputValue: "new_value"},
            };
            result.data.hook.update(null, mockVnode);

            // Should always update the value
            assert.strictEqual(mockTextarea.value, "new_value");
          });

          it("always overrides user input when value changes", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("textarea"),
              Type.list([
                Type.tuple([
                  Type.bitstring("value"),
                  Type.keywordList([
                    [
                      Type.atom("text"),
                      Type.bitstring("new_programmatic_value"),
                    ],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Simulate that user has typed something different
            mockTextarea.value = "user_typed_text";

            // Call the update hook with a new programmatic value
            const mockVnode = {
              elm: mockTextarea,
              data: {hologramFormInputValue: "new_programmatic_value"},
            };
            result.data.hook.update(null, mockVnode);

            // Should always update the value
            assert.strictEqual(mockTextarea.value, "new_programmatic_value");
          });

          it("updates value regardless of current textarea value", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("textarea"),
              Type.list([
                Type.tuple([
                  Type.bitstring("value"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("new_value")],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Simulate that current value is something else
            mockTextarea.value = "current_value";

            // Call the update hook
            const mockVnode = {
              elm: mockTextarea,
              data: {hologramFormInputValue: "new_value"},
            };
            result.data.hook.update(null, mockVnode);

            // Should always update the value
            assert.strictEqual(mockTextarea.value, "new_value");
          });

          it("sets value on any textarea element", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("textarea"),
              Type.list([
                Type.tuple([
                  Type.bitstring("value"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("first_value")],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Simulate textarea with any current value
            mockTextarea.value = "whatever";

            // Call the update hook
            const mockVnode = {
              elm: mockTextarea,
              data: {hologramFormInputValue: "first_value"},
            };
            result.data.hook.update(null, mockVnode);

            // Should always update the value
            assert.strictEqual(mockTextarea.value, "first_value");
          });

          it("does not update value when it hasn't changed", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("textarea"),
              Type.list([
                Type.tuple([
                  Type.bitstring("value"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("same_value")],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Set textarea to the same value as what will be set
            mockTextarea.value = "same_value";

            // Spy on the value setter to verify it's not called
            let setterCallCount = 0;
            const originalValue = mockTextarea.value;
            Object.defineProperty(mockTextarea, "value", {
              get: () => originalValue,
              set: () => {
                setterCallCount++;
              },
              configurable: true,
            });

            // Call the update hook with same value (to test no change)
            const oldVnode = {data: {hologramFormInputValue: "same_value"}};
            const mockVnode = {
              elm: mockTextarea,
              data: {hologramFormInputValue: "same_value"},
            };
            result.data.hook.update(oldVnode, mockVnode);

            // Should not have called the setter since value didn't change
            assert.strictEqual(setterCallCount, 0);
          });
        });
      });

      describe("checkbox element checked handling", () => {
        it("checkbox element with checked attribute sets up hooks", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("type"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("checkbox")],
                ]),
              ]),
              Type.tuple([
                Type.bitstring("checked"),
                Type.keywordList([
                  [Type.atom("expression"), Type.tuple([Type.boolean(true)])],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should not have the checked as an attribute
          assert.isUndefined(result.data.attrs.checked);

          // Should not have the temporary data-hologram-form-input-checked attribute
          assert.isUndefined(
            result.data.attrs["data-hologram-form-input-checked"],
          );

          // Should have the type attribute as a regular attribute
          assert.strictEqual(result.data.attrs.type, "checkbox");
          assert.deepStrictEqual(result.data.on, {});

          // Should have hooks set up
          assert.isObject(result.data.hook);
          assert.isFunction(result.data.hook.create);
          assert.isFunction(result.data.hook.update);

          // Should have hologramFormInputChecked data
          assert.strictEqual(result.data.hologramFormInputChecked, true);
        });

        it("checkbox element without checked attribute does not set up checked hooks", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("type"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("checkbox")],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should not have hooks
          assert.isUndefined(result.data.hook);
          assert.isUndefined(result.data.hologramFormInputChecked);
        });

        it("checkbox with true checked value", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("type"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("checkbox")],
                ]),
              ]),
              Type.tuple([
                Type.bitstring("checked"),
                Type.keywordList([
                  [Type.atom("expression"), Type.tuple([Type.boolean(true)])],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should have hologramFormInputChecked data set to false
          assert.strictEqual(result.data.hologramFormInputChecked, true);
        });

        it("checkbox with false checked value", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("type"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("checkbox")],
                ]),
              ]),
              Type.tuple([
                Type.bitstring("checked"),
                Type.keywordList([
                  [Type.atom("expression"), Type.tuple([Type.boolean(false)])],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should have hologramFormInputChecked data set to false
          assert.strictEqual(result.data.hologramFormInputChecked, false);
        });

        it("checkbox with nil checked value", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("type"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("checkbox")],
                ]),
              ]),
              Type.tuple([
                Type.bitstring("checked"),
                Type.keywordList([
                  [Type.atom("expression"), Type.tuple([Type.nil()])],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should have hologramFormInputChecked data set to false for nil
          assert.strictEqual(result.data.hologramFormInputChecked, false);
        });

        it("checkbox with non-empty string checked value", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("checked"),
                Type.keywordList([[Type.atom("text"), Type.bitstring("abc")]]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should convert string "true" to boolean true
          assert.strictEqual(result.data.hologramFormInputChecked, true);
        });

        it("checkbox with empty string checked value", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("checked"),
                Type.keywordList([[Type.atom("text"), Type.bitstring("")]]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should convert string "true" to boolean true
          assert.strictEqual(result.data.hologramFormInputChecked, true);
        });

        describe("checkbox checked handling during updates", () => {
          let mockInput;

          beforeEach(() => {
            mockInput = {
              tagName: "INPUT",
              type: "checkbox",
              checked: false,
            };
          });

          it("sets initial checked state on create hook", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("input"),
              Type.list([
                Type.tuple([
                  Type.bitstring("type"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("checkbox")],
                  ]),
                ]),
                Type.tuple([
                  Type.bitstring("checked"),
                  Type.keywordList([
                    [Type.atom("expression"), Type.tuple([Type.boolean(true)])],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Call the create hook
            const mockVnode = {
              elm: mockInput,
              data: {hologramFormInputChecked: true},
            };
            result.data.hook.create(null, mockVnode);

            // Should set the checked property
            assert.strictEqual(mockInput.checked, true);
          });

          it("always updates checked when checked changes", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("input"),
              Type.list([
                Type.tuple([
                  Type.bitstring("type"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("checkbox")],
                  ]),
                ]),
                Type.tuple([
                  Type.bitstring("checked"),
                  Type.keywordList([
                    [Type.atom("expression"), Type.tuple([Type.boolean(true)])],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Simulate input with any current checked state
            mockInput.checked = false;

            // Call the update hook
            const mockVnode = {
              elm: mockInput,
              data: {hologramFormInputChecked: true},
            };
            result.data.hook.update(null, mockVnode);

            // Should always update the checked state
            assert.strictEqual(mockInput.checked, true);
          });

          it("does not update checked when it hasn't changed", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("input"),
              Type.list([
                Type.tuple([
                  Type.bitstring("type"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("checkbox")],
                  ]),
                ]),
                Type.tuple([
                  Type.bitstring("checked"),
                  Type.keywordList([
                    [Type.atom("expression"), Type.tuple([Type.boolean(true)])],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Set input to the same checked state as what will be set
            mockInput.checked = true;

            // Spy on the checked setter to verify it's not called
            let setterCallCount = 0;
            const originalChecked = mockInput.checked;
            Object.defineProperty(mockInput, "checked", {
              get: () => originalChecked,
              set: () => {
                setterCallCount++;
              },
              configurable: true,
            });

            // Call the update hook with same checked state (to test no change)
            const oldVnode = {data: {hologramFormInputChecked: true}};
            const mockVnode = {
              elm: mockInput,
              data: {hologramFormInputChecked: true},
            };
            result.data.hook.update(oldVnode, mockVnode);

            // Should not have called the setter since checked didn't change
            assert.strictEqual(setterCallCount, 0);
          });
        });
      });

      describe("radio element handling", () => {
        it("radio element with value attribute treats value as regular attribute", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("type"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("radio")],
                ]),
              ]),
              Type.tuple([
                Type.bitstring("value"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("option1")],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should have the value as a regular attribute (not controlled)
          assert.strictEqual(result.data.attrs.value, "option1");

          // Should have the type attribute as a regular attribute
          assert.strictEqual(result.data.attrs.type, "radio");

          // Should not have hooks for value (since value is not controlled for radio)
          assert.isUndefined(result.data.hook);
          assert.isUndefined(result.data.hologramFormInputValue);
        });

        it("radio element with checked attribute sets up hooks", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("type"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("radio")],
                ]),
              ]),
              Type.tuple([
                Type.bitstring("checked"),
                Type.keywordList([
                  [Type.atom("expression"), Type.tuple([Type.boolean(true)])],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should not have the checked as an attribute
          assert.isUndefined(result.data.attrs.checked);

          // Should not have the temporary data-hologram-form-input-checked attribute
          assert.isUndefined(
            result.data.attrs["data-hologram-form-input-checked"],
          );

          // Should have the type attribute as a regular attribute
          assert.strictEqual(result.data.attrs.type, "radio");
          assert.deepStrictEqual(result.data.on, {});

          // Should have hooks set up
          assert.isObject(result.data.hook);
          assert.isFunction(result.data.hook.create);
          assert.isFunction(result.data.hook.update);

          // Should have hologramFormInputChecked data
          assert.strictEqual(result.data.hologramFormInputChecked, true);
        });

        it("radio element with both value and checked attributes handles them correctly", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("type"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("radio")],
                ]),
              ]),
              Type.tuple([
                Type.bitstring("value"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("option2")],
                ]),
              ]),
              Type.tuple([
                Type.bitstring("checked"),
                Type.keywordList([
                  [Type.atom("expression"), Type.tuple([Type.boolean(false)])],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should have the value as a regular attribute (not controlled)
          assert.strictEqual(result.data.attrs.value, "option2");

          // Should have the type attribute as a regular attribute
          assert.strictEqual(result.data.attrs.type, "radio");

          // Should not have the checked as an attribute (controlled)
          assert.isUndefined(result.data.attrs.checked);

          // Should have hooks set up for checked handling
          assert.isObject(result.data.hook);
          assert.isFunction(result.data.hook.create);
          assert.isFunction(result.data.hook.update);

          // Should have hologramFormInputChecked data set to false
          assert.strictEqual(result.data.hologramFormInputChecked, false);
        });

        it("radio element without checked attribute does not set up checked hooks", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("type"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("radio")],
                ]),
              ]),
              Type.tuple([
                Type.bitstring("value"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("option3")],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should have the value as a regular attribute
          assert.strictEqual(result.data.attrs.value, "option3");

          // Should have the type attribute as a regular attribute
          assert.strictEqual(result.data.attrs.type, "radio");

          // Should not have hooks
          assert.isUndefined(result.data.hook);
          assert.isUndefined(result.data.hologramFormInputChecked);
        });

        it("keeps $change event for radio element", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.list([
              Type.tuple([
                Type.bitstring("type"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("radio")],
                ]),
              ]),
              Type.tuple([
                Type.bitstring("$change"),
                Type.list([
                  Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const vdom = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          assert.deepStrictEqual(Object.keys(vdom.data.on), ["change"]);

          const stub = sinon
            .stub(Hologram, "handleUiEvent")
            .callsFake((..._args) => null);

          vdom.data.on.change("dummyEvent");

          sinon.assert.calledWith(
            stub,
            "dummyEvent",
            "change",
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
            ]),
            defaultTarget,
          );

          Hologram.handleUiEvent.restore();
        });
      });

      describe("select element value handling", () => {
        it("select element with value attribute sets up hooks", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("select"),
            Type.list([
              Type.tuple([
                Type.bitstring("value"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("option2")],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should not have the value as an attribute
          assert.isUndefined(result.data.attrs.value);

          // Should not have the temporary data-hologram-form-input-value attribute
          assert.isUndefined(
            result.data.attrs["data-hologram-form-input-value"],
          );

          // Should have hooks for handling the value property
          assert.strictEqual(typeof result.data.hook, "object");
          assert.strictEqual(typeof result.data.hook.create, "function");
          assert.strictEqual(typeof result.data.hook.update, "function");
        });

        it("select element without value attribute does not set up value hooks", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("select"),
            Type.list([
              Type.tuple([
                Type.bitstring("name"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("choices")],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should have the name attribute
          assert.strictEqual(result.data.attrs.name, "choices");

          // Should not have hooks since there's no value attribute
          assert.isUndefined(result.data.hook);
        });

        it("select element with empty string value attribute preserves empty string", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("select"),
            Type.list([
              Type.tuple([
                Type.bitstring("value"),
                Type.keywordList([[Type.atom("text"), Type.bitstring("")]]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should not have the value as an attribute
          assert.isUndefined(result.data.attrs.value);

          // Should not have the temporary data-hologram-form-input-value attribute
          assert.isUndefined(
            result.data.attrs["data-hologram-form-input-value"],
          );

          // Should have hooks for handling the value property
          assert.strictEqual(typeof result.data.hook, "object");
          assert.strictEqual(typeof result.data.hook.create, "function");
          assert.strictEqual(typeof result.data.hook.update, "function");
        });

        it("select element with undefined value does not set up hooks", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("select"),
            Type.list([
              Type.tuple([
                Type.bitstring("value"),
                Type.keywordList([
                  [Type.atom("expression"), Type.tuple([Type.nil()])],
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          // Should not have the value as an attribute
          assert.isUndefined(result.data.attrs.value);

          // Should not have the temporary data-hologram-form-input-value attribute
          assert.isUndefined(
            result.data.attrs["data-hologram-form-input-value"],
          );

          // Should not have hooks
          assert.isUndefined(result.data.hook);
        });

        describe("select value handling during updates", () => {
          let mockSelect;

          beforeEach(() => {
            mockSelect = {
              tagName: "SELECT",
              value: "",
            };
          });

          it("sets initial value on create hook", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("select"),
              Type.list([
                Type.tuple([
                  Type.bitstring("value"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("option1")],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Call the create hook with mock vnode
            const mockVnode = {elm: mockSelect};
            result.data.hook.create(null, mockVnode);

            // Should set the value
            assert.strictEqual(mockSelect.value, "option1");
          });

          it("always updates value on update hook", () => {
            const node = Type.tuple([
              Type.atom("element"),
              Type.bitstring("select"),
              Type.list([
                Type.tuple([
                  Type.bitstring("value"),
                  Type.keywordList([
                    [Type.atom("text"), Type.bitstring("option2")],
                  ]),
                ]),
              ]),
              Type.list(),
            ]);

            const result = Renderer.renderDom(
              node,
              context,
              slots,
              defaultTarget,
              parentTagName,
            );

            // Simulate that we previously set a value
            mockSelect.value = "option1";

            // Call the update hook
            const mockVnode = {
              elm: mockSelect,
              data: {hologramFormInputValue: "option2"},
            };
            result.data.hook.update(null, mockVnode);

            // Should always update the value
            assert.strictEqual(mockSelect.value, "option2");
          });
        });

        it("keeps $change event for select element", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("select"),
            Type.list([
              Type.tuple([
                Type.bitstring("$change"),
                Type.list([
                  Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
                ]),
              ]),
            ]),
            Type.list(),
          ]);

          const vdom = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          assert.deepStrictEqual(Object.keys(vdom.data.on), ["change"]);

          const stub = sinon
            .stub(Hologram, "handleUiEvent")
            .callsFake((..._args) => null);

          vdom.data.on.change("dummyEvent");

          sinon.assert.calledWith(
            stub,
            "dummyEvent",
            "change",
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
            ]),
            defaultTarget,
          );

          Hologram.handleUiEvent.restore();
        });
      });
    });
  });

  describe("element spread", () => {
    const spread = (value) =>
      Type.tuple([Type.atom("spread"), Type.tuple([value])]);

    const namedAttr = (name, valueDom) =>
      Type.tuple([Type.bitstring(name), valueDom]);

    const textValue = (text) =>
      Type.keywordList([[Type.atom("text"), Type.bitstring(text)]]);

    const renderElement = (tagName, attrsDom) =>
      Renderer.renderDom(
        Type.tuple([
          Type.atom("element"),
          Type.bitstring(tagName),
          Type.list(attrsDom),
          Type.list(),
        ]),
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

    const assertRaises = (attrsDom, errorType, message) =>
      assertBoxedError(
        () => renderElement("div", attrsDom),
        errorType,
        message,
      );

    it("map value", () => {
      const attrsDom = [
        spread(Type.map([[Type.atom("id"), Type.bitstring("my_id")]])),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {id: "my_id"}, on: {}}, []),
      );
    });

    it("keyword list value", () => {
      const attrsDom = [
        spread(
          Type.keywordList([
            [Type.atom("id"), Type.bitstring("my_id")],
            [Type.atom("class"), Type.bitstring("my_class")],
          ]),
        ),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {class: "my_class", id: "my_id"}, on: {}}, []),
      );
    });

    it("map value with multiple entries", () => {
      const attrsDom = [
        spread(
          Type.map([
            [Type.atom("id"), Type.bitstring("my_id")],
            [Type.atom("class"), Type.bitstring("my_class")],
          ]),
        ),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {class: "my_class", id: "my_id"}, on: {}}, []),
      );
    });

    it("string keys", () => {
      const attrsDom = [
        spread(Type.map([[Type.bitstring("id"), Type.bitstring("my_id")]])),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {id: "my_id"}, on: {}}, []),
      );
    });

    it("entries are sorted by name, regardless of key type", () => {
      const attrsDom = [
        spread(
          Type.map([
            [Type.atom("my_key_3"), Type.bitstring("c")],
            [Type.bitstring("my_key_1"), Type.bitstring("a")],
            [Type.atom("my_key_2"), Type.bitstring("b")],
          ]),
        ),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode(
          "div",
          {
            attrs: {"my-key-1": "a", "my-key-2": "b", "my-key-3": "c"},
            on: {},
          },
          [],
        ),
      );
    });

    it("entries are sorted by the composed name, so nested ones stay next to their siblings", () => {
      const attrsDom = [
        spread(
          Type.keywordList([
            [Type.atom("my_key_2"), Type.bitstring("b")],
            [
              Type.atom("data"),
              Type.keywordList([
                [Type.atom("user_id"), Type.integer(1)],
                [Type.atom("role"), Type.bitstring("admin")],
              ]),
            ],
            [Type.atom("my_key_1"), Type.bitstring("a")],
          ]),
        ),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode(
          "div",
          {
            attrs: {
              "data-role": "admin",
              "data-user-id": "1",
              "my-key-1": "a",
              "my-key-2": "b",
            },
            on: {},
          },
          [],
        ),
      );
    });

    it("underscores in an atom key are converted to hyphens", () => {
      const attrsDom = [
        spread(Type.map([[Type.atom("my_key"), Type.bitstring("my_value")]])),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {"my-key": "my_value"}, on: {}}, []),
      );
    });

    it("underscores in a string key are converted to hyphens", () => {
      const attrsDom = [
        spread(
          Type.map([[Type.bitstring("my_key"), Type.bitstring("my_value")]]),
        ),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {"my-key": "my_value"}, on: {}}, []),
      );
    });

    it("nested map value composes a dash-joined name", () => {
      const attrsDom = [
        spread(
          Type.map([
            [
              Type.atom("data"),
              Type.map([[Type.atom("user_id"), Type.integer(1)]]),
            ],
          ]),
        ),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {"data-user-id": "1"}, on: {}}, []),
      );
    });

    it("nested keyword list value composes a dash-joined name", () => {
      const attrsDom = [
        spread(
          Type.keywordList([
            [
              Type.atom("data"),
              Type.keywordList([[Type.atom("user_id"), Type.integer(1)]]),
            ],
          ]),
        ),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {"data-user-id": "1"}, on: {}}, []),
      );
    });

    it("map nested in a keyword list", () => {
      const attrsDom = [
        spread(
          Type.keywordList([
            [
              Type.atom("data"),
              Type.map([[Type.atom("user_id"), Type.integer(1)]]),
            ],
          ]),
        ),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {"data-user-id": "1"}, on: {}}, []),
      );
    });

    it("keyword list nested in a map", () => {
      const attrsDom = [
        spread(
          Type.map([
            [
              Type.atom("data"),
              Type.keywordList([[Type.atom("user_id"), Type.integer(1)]]),
            ],
          ]),
        ),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {"data-user-id": "1"}, on: {}}, []),
      );
    });

    it("nesting at multiple levels", () => {
      const attrsDom = [
        spread(
          Type.keywordList([
            [
              Type.atom("data"),
              Type.keywordList([
                [
                  Type.atom("my_group"),
                  Type.map([[Type.atom("my_key"), Type.bitstring("my_value")]]),
                ],
              ]),
            ],
          ]),
        ),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {"data-my-group-my-key": "my_value"}, on: {}}, []),
      );
    });

    // Sorting is stable, so a keyword list's order still decides which duplicate key wins.
    it("duplicate keys in a keyword list, later wins", () => {
      const attrsDom = [
        spread(
          Type.keywordList([
            [Type.atom("id"), Type.bitstring("my_value_1")],
            [Type.atom("id"), Type.bitstring("my_value_2")],
          ]),
        ),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {id: "my_value_2"}, on: {}}, []),
      );
    });

    it("entry with nil value is not rendered", () => {
      const attrsDom = [
        spread(
          Type.keywordList([
            [Type.atom("id"), Type.nil()],
            [Type.atom("class"), Type.bitstring("my_class")],
          ]),
        ),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {class: "my_class"}, on: {}}, []),
      );
    });

    it("entry with false value is not rendered", () => {
      const attrsDom = [
        spread(
          Type.keywordList([
            [Type.atom("id"), Type.boolean(false)],
            [Type.atom("class"), Type.bitstring("my_class")],
          ]),
        ),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {class: "my_class"}, on: {}}, []),
      );
    });

    it("entry with true value is stringified, same as a named attribute", () => {
      const attrsDom = [
        spread(Type.map([[Type.atom("id"), Type.boolean(true)]])),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {id: "true"}, on: {}}, []),
      );
    });

    it("entry with empty string value renders the bare name, same as a named attribute", () => {
      const attrsDom = [
        spread(Type.map([[Type.atom("id"), Type.bitstring("")]])),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {id: true}, on: {}}, []),
      );
    });

    // Only maps and keyword lists recurse, so a non-keyword list nested inside a spread is a value.
    // String.Chars is stubbed in these tests, hence the dummy stringification result.
    it("nested list which is not a keyword list is a leaf and is stringified", () => {
      const attrsDom = [
        spread(Type.map([[Type.atom("my_key"), Type.charlist("abc")]])),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode(
          "div",
          {
            attrs: {"my-key": "Dummy String.Chars protocol result"},
            on: {},
          },
          [],
        ),
      );
    });

    it("empty map value renders no attributes", () => {
      assert.deepStrictEqual(
        renderElement("div", [spread(Type.map())]),
        vnode("div", {attrs: {}, on: {}}, []),
      );
    });

    it("empty keyword list value renders no attributes", () => {
      assert.deepStrictEqual(
        renderElement("div", [spread(Type.keywordList())]),
        vnode("div", {attrs: {}, on: {}}, []),
      );
    });

    it("void element", () => {
      const attrsDom = [
        spread(Type.map([[Type.atom("id"), Type.bitstring("my_id")]])),
      ];

      assert.deepStrictEqual(
        renderElement("img", attrsDom),
        vnode("img", {attrs: {id: "my_id"}, on: {}}, []),
      );
    });

    it("named attribute before the spread is overridden", () => {
      const attrsDom = [
        namedAttr("id", textValue("my_value_1")),
        spread(Type.map([[Type.atom("id"), Type.bitstring("my_value_2")]])),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {id: "my_value_2"}, on: {}}, []),
      );
    });

    it("named attribute after the spread wins", () => {
      const attrsDom = [
        spread(Type.map([[Type.atom("id"), Type.bitstring("my_value_1")]])),
        namedAttr("id", textValue("my_value_2")),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {id: "my_value_2"}, on: {}}, []),
      );
    });

    it("later spread wins over an earlier one", () => {
      const attrsDom = [
        spread(Type.map([[Type.atom("id"), Type.bitstring("my_value_1")]])),
        spread(Type.map([[Type.atom("id"), Type.bitstring("my_value_2")]])),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {id: "my_value_2"}, on: {}}, []),
      );
    });

    // A named attribute which is overridden by a spread must not survive as a leftover, even when
    // the winning entry renders nothing.
    it("named attribute overridden by a nil spread entry is dropped", () => {
      const attrsDom = [
        namedAttr("id", textValue("my_value")),
        spread(Type.map([[Type.atom("id"), Type.nil()]])),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode("div", {attrs: {}, on: {}}, []),
      );
    });

    // Only the block a single spread expands to is sorted.
    it("sorting doesn't move attributes written literally", () => {
      const attrsDom = [
        namedAttr("zzz", textValue("my_value_1")),
        spread(
          Type.map([
            [Type.atom("bbb"), Type.bitstring("my_value_2")],
            [Type.atom("aaa"), Type.bitstring("my_value_3")],
          ]),
        ),
        namedAttr("yyy", textValue("my_value_4")),
      ];

      assert.deepStrictEqual(
        Object.keys(renderElement("div", attrsDom).data.attrs),
        ["zzz", "aaa", "bbb", "yyy"],
      );
    });

    it("each spread is sorted on its own", () => {
      const attrsDom = [
        spread(
          Type.map([
            [Type.atom("zzz"), Type.bitstring("my_value_1")],
            [Type.atom("aaa"), Type.bitstring("my_value_2")],
          ]),
        ),
        spread(Type.map([[Type.atom("bbb"), Type.bitstring("my_value_3")]])),
      ];

      assert.deepStrictEqual(
        Object.keys(renderElement("div", attrsDom).data.attrs),
        ["aaa", "zzz", "bbb"],
      );
    });

    it("interleaved with named attributes", () => {
      const attrsDom = [
        namedAttr("attr_1", textValue("my_value_1")),
        spread(Type.map([[Type.atom("attr_2"), Type.bitstring("my_value_2")]])),
        namedAttr(
          "attr_3",
          Type.keywordList([
            [
              Type.atom("expression"),
              Type.tuple([Type.bitstring("my_value_3")]),
            ],
          ]),
        ),
      ];

      assert.deepStrictEqual(
        renderElement("div", attrsDom),
        vnode(
          "div",
          {
            attrs: {
              attr_1: "my_value_1",
              "attr-2": "my_value_2",
              attr_3: "my_value_3",
            },
            on: {},
          },
          [],
        ),
      );
    });

    // Client-only: the controlled-input path reads the type and value attributes back out of the
    // expanded list, so a spread has to reach it the same way a named attribute does.
    it("controlled input value supplied through a spread", () => {
      const attrsDom = [
        spread(
          Type.map([
            [Type.atom("type"), Type.bitstring("email")],
            [Type.atom("value"), Type.bitstring("my_value")],
          ]),
        ),
      ];

      const result = renderElement("input", attrsDom);

      assert.isUndefined(result.data.attrs.value);
      assert.isUndefined(result.data.attrs["data-hologram-form-input-value"]);
      assert.strictEqual(result.data.hologramFormInputValue, "my_value");
      assert.strictEqual(typeof result.data.hook, "object");
    });

    it("raises for a nil value", () => {
      assertRaises(
        [spread(Type.nil())],
        "ArgumentError",
        "spread value must be a map or a keyword list, got: nil",
      );
    });

    it("raises for a string value", () => {
      assertRaises(
        [spread(Type.bitstring("my_string"))],
        "ArgumentError",
        'spread value must be a map or a keyword list, got: "my_string"',
      );
    });

    it("raises for a list which is not a keyword list", () => {
      assertRaises(
        [
          spread(
            Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
          ),
        ],
        "ArgumentError",
        "spread value must be a map or a keyword list, got: [1, 2, 3]",
      );
    });

    it("raises for a struct value", () => {
      const structDom = Type.map([
        [Type.atom("__struct__"), Type.alias("Aaa.Bbb")],
        [Type.atom("my_key"), Type.integer(1)],
      ]);

      assertRaises(
        [spread(structDom)],
        "ArgumentError",
        `spread value must be a map or a keyword list, got: ${Interpreter.inspect(structDom)}`,
      );
    });

    it("raises for a '$'-prefixed atom key", () => {
      assertRaises(
        [spread(Type.map([[Type.atom("$click"), Type.atom("my_command")]]))],
        "ArgumentError",
        `event bindings can't be set through a spread, got the "$click" key`,
      );
    });

    it("raises for a '$'-prefixed string key", () => {
      assertRaises(
        [
          spread(
            Type.map([[Type.bitstring("$click"), Type.atom("my_command")]]),
          ),
        ],
        "ArgumentError",
        `event bindings can't be set through a spread, got the "$click" key`,
      );
    });

    it("raises for a '$'-prefixed nested key", () => {
      assertRaises(
        [
          spread(
            Type.map([
              [
                Type.atom("data"),
                Type.map([[Type.bitstring("$click"), Type.atom("my_command")]]),
              ],
            ]),
          ),
        ],
        "ArgumentError",
        `event bindings can't be set through a spread, got the "$click" key`,
      );
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
          Type.list(),
          Type.list(),
        ]),
        Type.tuple([Type.atom("text"), Type.bitstring("bbb")]),
      ]);

      const result = Renderer.renderDom(
        nodes,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = ["aaa", vnode("div", {attrs: {}, on: {}}, []), "bbb"];

      assert.deepStrictEqual(result, expected);
    });

    it("multiple nodes with merging", () => {
      const nodes = Type.list([
        Type.tuple([Type.atom("text"), Type.bitstring("aaa")]),
        Type.tuple([Type.atom("expression"), Type.tuple([Type.integer(111)])]),
        Type.tuple([Type.atom("text"), Type.bitstring("bbb")]),
        Type.tuple([Type.atom("expression"), Type.tuple([Type.integer(222)])]),
      ]);

      const result = Renderer.renderDom(
        nodes,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, ["aaa111bbb222"]);
    });

    it("nil nodes", () => {
      const nodes = Type.list([
        Type.tuple([Type.atom("text"), Type.bitstring("aaa")]),
        Type.nil(),
        Type.tuple([Type.atom("text"), Type.bitstring("bbb")]),
        Type.nil(),
      ]);

      const result = Renderer.renderDom(
        nodes,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, ["aaabbb"]);
    });

    it("drops nil results rendered by window and document nodes", () => {
      // aaa<window $key_down="my_action" />bbb<document $key_up="my_action" />
      const actionSpecDom = Type.list([
        Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
      ]);

      const nodes = Type.list([
        Type.tuple([Type.atom("text"), Type.bitstring("aaa")]),
        Type.tuple([
          Type.atom("element"),
          Type.bitstring("window"),
          Type.list([Type.tuple([Type.bitstring("$key_down"), actionSpecDom])]),
          Type.list(),
        ]),
        Type.tuple([Type.atom("text"), Type.bitstring("bbb")]),
        Type.tuple([
          Type.atom("element"),
          Type.bitstring("document"),
          Type.list([Type.tuple([Type.bitstring("$key_up"), actionSpecDom])]),
          Type.list(),
        ]),
      ]);

      Renderer.listenerBindings = [];

      const result = Renderer.renderDom(
        nodes,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

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
          Type.list(),
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
          Type.list(),
        ]),
      ]);

      const entry3 = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module3"),
        state: Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
        ]),
      });

      ComponentRegistry.putEntry(cid3, entry3);

      const entry7 = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module7"),
        state: Type.map([
          [Type.atom("c"), Type.integer(3)],
          [Type.atom("d"), Type.integer(4)],
        ]),
      });

      ComponentRegistry.putEntry(cid7, entry7);

      const result = Renderer.renderDom(
        nodes,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, [
        "abc",
        vnode("div", {attrs: {}, on: {}}, ["state_a = 1, state_b = 2"]),
        "xyz",
        vnode("div", {attrs: {}, on: {}}, ["state_c = 3, state_d = 4"]),
      ]);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([
          [cid3, entry3],
          [cid7, entry7],
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
          Type.list(),
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
          Type.list(),
        ]),
      ]);

      const entry51 = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module51"),
        state: Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
        ]),
      });

      ComponentRegistry.putEntry(cid51, entry51);

      const entry52 = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module52"),
        state: Type.map([
          [Type.atom("c"), Type.integer(3)],
          [Type.atom("d"), Type.integer(4)],
        ]),
      });

      ComponentRegistry.putEntry(cid52, entry52);

      const result = Renderer.renderDom(
        nodes,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, [
        "abc",
        vnode("div", {attrs: {}, on: {}}, ["state_a = 1"]),
        vnode("div", {attrs: {}, on: {}}, ["state_b = 2"]),
        "xyz",
        vnode("div", {attrs: {}, on: {}}, ["state_c = 3"]),
        vnode("div", {attrs: {}, on: {}}, ["state_d = 4"]),
      ]);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([
          [cid51, entry51],
          [cid52, entry52],
        ]),
      );
    });
  });

  describe("component props", () => {
    it("single-valued", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module64"),
        Type.list([
          Type.tuple([
            Type.bitstring("my_prop"),
            Type.keywordList([
              [Type.atom("expression"), Type.tuple([Type.integer(123)])],
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = ["my_prop = 123"];

      assert.deepStrictEqual(result, expected);
    });

    it("multi-valued", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module64"),
        Type.list([
          Type.tuple([
            Type.bitstring("my_prop"),
            Type.keywordList([
              [
                Type.atom("expression"),
                Type.tuple([Type.integer(1), Type.integer(2), Type.integer(3)]),
              ],
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = ["my_prop = {1, 2, 3}"];

      assert.deepStrictEqual(result, expected);
    });

    it("default value specified", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module65"),
        Type.list([
          Type.tuple([
            Type.bitstring("prop_2"),
            Type.keywordList([
              [Type.atom("expression"), Type.tuple([Type.atom("xyz")])],
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = [
        'component vars = %{prop_1: "abc", prop_2: :xyz, prop_3: 123}',
      ];

      assert.deepStrictEqual(result, expected);
    });

    it("default value not specified", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module66"),
        Type.list([
          Type.tuple([
            Type.bitstring("prop_2"),
            Type.keywordList([
              [Type.atom("expression"), Type.tuple([Type.atom("xyz")])],
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = ["component vars = %{prop_2: :xyz}"];

      assert.deepStrictEqual(result, expected);
    });

    it("declared to take value from context, value in context", () => {
      const context = Type.map([
        [
          Type.tuple([Type.atom("my_scope"), Type.atom("my_key")]),
          Type.integer(123),
        ],
      ]);

      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module37"),
        Type.list([
          Type.tuple([
            Type.bitstring("cid"),
            Type.keywordList([
              [Type.atom("text"), Type.bitstring("component_37")],
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      initComponentRegistryEntry(
        Type.bitstring("component_37"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module37"),
      );

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = ["prop_aaa = 123"];

      assert.deepStrictEqual(result, expected);
    });

    it("declared to take value from context, value not in context, default value not specified", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module76"),
        Type.list([
          Type.tuple([
            Type.bitstring("cid"),
            Type.keywordList([
              [Type.atom("text"), Type.bitstring("component_76")],
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      initComponentRegistryEntry(
        Type.bitstring("component_76"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module76"),
      );

      assertBoxedError(
        () =>
          Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          ),
        "KeyError",
        buildKeyErrorMsg(Type.atom("aaa"), Type.map()),
      );
    });

    it("declared to take value from context, value not in context, default value specified", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module77"),
        Type.list([
          Type.tuple([
            Type.bitstring("cid"),
            Type.keywordList([
              [Type.atom("text"), Type.bitstring("component_77")],
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      initComponentRegistryEntry(
        Type.bitstring("component_77"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module77"),
      );

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = ["prop_aaa = 987"];

      assert.deepStrictEqual(result, expected);
    });

    it("required prop given", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module89"),
        Type.list([
          Type.tuple([
            Type.bitstring("aaa"),
            Type.keywordList([[Type.atom("text"), Type.bitstring("my_value")]]),
          ]),
        ]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, ["prop_aaa = my_value"]);
    });

    it("required prop missing", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module89"),
        Type.list(),
        Type.list(),
      ]);

      assertBoxedError(
        () =>
          Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          ),
        "Hologram.PropError",
        'component "Hologram.Test.Fixtures.Template.Renderer.Module89" is missing required prop "aaa"',
      );
    });

    it("required prop missing, rendered from a parent template", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module89"),
        Type.list(),
        Type.list(),
      ]);

      assertBoxedError(
        () =>
          Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
            Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module64"),
            null,
          ),
        "Hologram.PropError",
        'component "Hologram.Test.Fixtures.Template.Renderer.Module89" is missing required prop "aaa", ' +
          'rendered from "Hologram.Test.Fixtures.Template.Renderer.Module64"',
      );
    });

    it("prop value in the :values list", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module91"),
        Type.list([
          Type.tuple([
            Type.bitstring("aaa"),
            Type.keywordList([
              [Type.atom("expression"), Type.tuple([Type.atom("small")])],
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, ["component vars = %{aaa: :small}"]);
    });

    it("prop value not in the :values list", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module91"),
        Type.list([
          Type.tuple([
            Type.bitstring("aaa"),
            Type.keywordList([
              [Type.atom("expression"), Type.tuple([Type.atom("huge")])],
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      assertBoxedError(
        () =>
          Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          ),
        "Hologram.PropError",
        'prop "aaa" of component "Hologram.Test.Fixtures.Template.Renderer.Module91" ' +
          "must be one of [:small, :large], got: :huge",
      );
    });

    it("absent prop with a :values list doesn't raise", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module91"),
        Type.list(),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, ["component vars = %{}"]);
    });
  });

  describe("component prop spread", () => {
    const module16 = Type.alias(
      "Hologram.Test.Fixtures.Template.Renderer.Module16",
    );

    const module86 = Type.alias(
      "Hologram.Test.Fixtures.Template.Renderer.Module86",
    );

    const spread = (value) =>
      Type.tuple([Type.atom("spread"), Type.tuple([value])]);

    const namedProp = (name, text) =>
      Type.tuple([
        Type.bitstring(name),
        Type.keywordList([[Type.atom("text"), Type.bitstring(text)]]),
      ]);

    const renderComponent = (moduleAlias, propsDom) =>
      Renderer.renderDom(
        Type.tuple([
          Type.atom("component"),
          moduleAlias,
          Type.list(propsDom),
          Type.list(),
        ]),
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

    const assertRaises = (propsDom, errorType, message) =>
      assertBoxedError(
        () => renderComponent(module16, propsDom),
        errorType,
        message,
      );

    it("map value", () => {
      const propsDom = [
        spread(
          Type.map([
            [Type.atom("prop_1"), Type.bitstring("my_value_1")],
            [Type.atom("prop_2"), Type.integer(2)],
          ]),
        ),
      ];

      assert.deepStrictEqual(renderComponent(module16, propsDom), [
        'component vars = %{prop_1: "my_value_1", prop_2: 2}',
      ]);
    });

    it("keyword list value", () => {
      const propsDom = [
        spread(
          Type.keywordList([
            [Type.atom("prop_1"), Type.bitstring("my_value_1")],
            [Type.atom("prop_2"), Type.integer(2)],
          ]),
        ),
      ];

      assert.deepStrictEqual(renderComponent(module16, propsDom), [
        'component vars = %{prop_1: "my_value_1", prop_2: 2}',
      ]);
    });

    it("string keys", () => {
      const propsDom = [
        spread(
          Type.map([[Type.bitstring("prop_1"), Type.bitstring("my_value_1")]]),
        ),
      ];

      assert.deepStrictEqual(renderComponent(module16, propsDom), [
        'component vars = %{prop_1: "my_value_1"}',
      ]);
    });

    // Prop names live in the Elixir namespace, so they are not dasherized the way attributes are.
    it("underscores in names are kept verbatim", () => {
      const propsDom = [
        spread(
          Type.map([[Type.atom("my_prop_1"), Type.bitstring("my_value_1")]]),
        ),
      ];

      assert.deepStrictEqual(renderComponent(module86, propsDom), [
        'component vars = %{my_prop_1: "my_value_1"}',
      ]);
    });

    it("undeclared keys are filtered out", () => {
      const propsDom = [
        spread(
          Type.map([
            [Type.atom("prop_1"), Type.bitstring("my_value_1")],
            [Type.atom("undeclared"), Type.bitstring("my_value_2")],
          ]),
        ),
      ];

      assert.deepStrictEqual(renderComponent(module16, propsDom), [
        'component vars = %{prop_1: "my_value_1"}',
      ]);
    });

    it("values are passed as raw terms", () => {
      const propsDom = [
        spread(
          Type.map([
            [
              Type.atom("my_prop"),
              Type.tuple([Type.integer(1), Type.integer(2), Type.integer(3)]),
            ],
          ]),
        ),
      ];

      assert.deepStrictEqual(
        renderComponent(
          Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module64"),
          propsDom,
        ),
        ["my_prop = {1, 2, 3}"],
      );
    });

    // Unlike the element branch, a map value doesn't recurse into composed names.
    it("map value of an entry is a raw prop value", () => {
      const propsDom = [
        spread(
          Type.map([
            [
              Type.atom("my_prop_2"),
              Type.map([[Type.atom("my_nested_key"), Type.integer(1)]]),
            ],
          ]),
        ),
      ];

      assert.deepStrictEqual(renderComponent(module86, propsDom), [
        "component vars = %{my_prop_2: %{my_nested_key: 1}}",
      ]);
    });

    it("keyword list value of an entry is a raw prop value", () => {
      const propsDom = [
        spread(
          Type.map([
            [
              Type.atom("my_prop_3"),
              Type.keywordList([[Type.atom("my_nested_key"), Type.integer(1)]]),
            ],
          ]),
        ),
      ];

      assert.deepStrictEqual(renderComponent(module86, propsDom), [
        "component vars = %{my_prop_3: [my_nested_key: 1]}",
      ]);
    });

    it("nil value is passed as-is", () => {
      const propsDom = [
        spread(Type.map([[Type.atom("my_prop_1"), Type.nil()]])),
      ];

      assert.deepStrictEqual(renderComponent(module86, propsDom), [
        "component vars = %{my_prop_1: nil}",
      ]);
    });

    it("false value is passed as-is", () => {
      const propsDom = [
        spread(Type.map([[Type.atom("my_prop_1"), Type.boolean(false)]])),
      ];

      assert.deepStrictEqual(renderComponent(module86, propsDom), [
        "component vars = %{my_prop_1: false}",
      ]);
    });

    it("named prop before the spread is overridden", () => {
      const propsDom = [
        namedProp("prop_1", "my_value_1"),
        spread(Type.map([[Type.atom("prop_1"), Type.bitstring("my_value_2")]])),
      ];

      assert.deepStrictEqual(renderComponent(module16, propsDom), [
        'component vars = %{prop_1: "my_value_2"}',
      ]);
    });

    it("named prop after the spread wins", () => {
      const propsDom = [
        spread(Type.map([[Type.atom("prop_1"), Type.bitstring("my_value_1")]])),
        namedProp("prop_1", "my_value_2"),
      ];

      assert.deepStrictEqual(renderComponent(module16, propsDom), [
        'component vars = %{prop_1: "my_value_2"}',
      ]);
    });

    it("later spread wins over an earlier one", () => {
      const propsDom = [
        spread(Type.map([[Type.atom("prop_1"), Type.bitstring("my_value_1")]])),
        spread(Type.map([[Type.atom("prop_1"), Type.bitstring("my_value_2")]])),
      ];

      assert.deepStrictEqual(renderComponent(module16, propsDom), [
        'component vars = %{prop_1: "my_value_2"}',
      ]);
    });

    it("cid supplied through a spread initializes a stateful component", () => {
      const propsDom = [
        spread(
          Type.map([
            [Type.atom("cid"), Type.bitstring("my_component")],
            [Type.atom("prop_1"), Type.bitstring("my_value")],
          ]),
        ),
      ];

      initComponentRegistryEntry(
        Type.bitstring("my_component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module16"),
      );

      assert.deepStrictEqual(renderComponent(module16, propsDom), [
        'component vars = %{cid: "my_component", prop_1: "my_value"}',
      ]);
    });

    // Module3 is uninitialized here and declares no props, so its state can only reach the template
    // through the stateful path, which the cid arriving via the spread is what selects.
    it("cid supplied through a spread runs init and merges the resulting state into vars", () => {
      const module3 = Type.alias(
        "Hologram.Test.Fixtures.Template.Renderer.Module3",
      );

      const cid = Type.bitstring("my_component");
      const propsDom = [spread(Type.map([[Type.atom("cid"), cid]]))];

      assert.deepStrictEqual(renderComponent(module3, propsDom), [
        vnode("div", {attrs: {}, on: {}}, ["state_a = 11, state_b = 22"]),
      ]);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([
          [
            cid,
            componentRegistryEntryFixture({
              module: module3,
              state: Type.map([
                [Type.atom("a"), Type.integer(11)],
                [Type.atom("b"), Type.integer(22)],
              ]),
            }),
          ],
        ]),
      );
    });

    it("declared default value is applied for a key not supplied by the spread", () => {
      const propsDom = [
        spread(Type.map([[Type.atom("prop_2"), Type.atom("my_value")]])),
      ];

      assert.deepStrictEqual(
        renderComponent(
          Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module65"),
          propsDom,
        ),
        ['component vars = %{prop_1: "abc", prop_2: :my_value, prop_3: 123}'],
      );
    });

    it("empty map value supplies no props", () => {
      const propsDom = [namedProp("prop_1", "my_value_1"), spread(Type.map())];

      assert.deepStrictEqual(renderComponent(module16, propsDom), [
        'component vars = %{prop_1: "my_value_1"}',
      ]);
    });

    it("raises for a nil value", () => {
      assertRaises(
        [spread(Type.nil())],
        "ArgumentError",
        "spread value must be a map or a keyword list, got: nil",
      );
    });

    it("raises for a string value", () => {
      assertRaises(
        [spread(Type.bitstring("my_string"))],
        "ArgumentError",
        'spread value must be a map or a keyword list, got: "my_string"',
      );
    });

    it("raises for a list which is not a keyword list", () => {
      assertRaises(
        [
          spread(
            Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
          ),
        ],
        "ArgumentError",
        "spread value must be a map or a keyword list, got: [1, 2, 3]",
      );
    });

    it("raises for a struct value", () => {
      const structDom = Type.map([
        [Type.atom("__struct__"), Type.alias("Aaa.Bbb")],
        [Type.atom("my_key"), Type.integer(1)],
      ]);

      assertRaises(
        [spread(structDom)],
        "ArgumentError",
        `spread value must be a map or a keyword list, got: ${Interpreter.inspect(structDom)}`,
      );
    });

    it("raises for a '$'-prefixed key", () => {
      assertRaises(
        [
          spread(
            Type.map([[Type.bitstring("$click"), Type.atom("my_command")]]),
          ),
        ],
        "ArgumentError",
        `event bindings can't be set through a spread, got the "$click" key`,
      );
    });
  });

  describe("stateless component", () => {
    it("without props", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module1"),
        Type.list(),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = [vnode("div", {attrs: {}, on: {}}, ["abc"])];

      assert.deepStrictEqual(result, expected);

      assert.deepStrictEqual(ComponentRegistry.entries, Type.map());
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
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = [
        vnode("div", {attrs: {}, on: {}}, [
          "prop_a = ddd, prop_b = 222, prop_c = fff333hhh",
        ]),
      ];

      assert.deepStrictEqual(result, expected);

      assert.deepStrictEqual(ComponentRegistry.entries, Type.map());
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
        Type.list(),
      ]);

      assertBoxedError(
        () =>
          Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          ),
        "KeyError",
        buildKeyErrorMsg(
          Type.atom("b"),
          Type.map([[Type.atom("a"), Type.bitstring("111")]]),
        ),
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
        Type.list(),
      ]);

      initComponentRegistryEntry(
        cid,
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module1"),
      );

      const resultVDom = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expectedVdom = [vnode("div", {attrs: {}, on: {}}, ["abc"])];
      assert.deepStrictEqual(resultVDom, expectedVdom);

      const expectedComponentRegistryEntries = Type.map([
        [
          cid,
          componentRegistryEntryFixture({
            module: Type.alias(
              "Hologram.Test.Fixtures.Template.Renderer.Module1",
            ),
          }),
        ],
      ]);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        expectedComponentRegistryEntries,
      );
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
        Type.list(),
      ]);

      initComponentRegistryEntry(
        cid,
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module2"),
      );

      const resultVDom = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expectedVdom = [
        vnode("div", {attrs: {}, on: {}}, [
          "prop_a = ddd, prop_b = 222, prop_c = fff333hhh",
        ]),
      ];

      assert.deepStrictEqual(resultVDom, expectedVdom);

      const expectedComponentRegistryEntries = Type.map([
        [
          cid,
          componentRegistryEntryFixture({
            module: Type.alias(
              "Hologram.Test.Fixtures.Template.Renderer.Module2",
            ),
          }),
        ],
      ]);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        expectedComponentRegistryEntries,
      );
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
        Type.list(),
      ]);

      const entry = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module3"),
        state: Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
        ]),
      });

      ComponentRegistry.putEntry(cid, entry);

      const resultVDom = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expectedVdom = [
        vnode("div", {attrs: {}, on: {}}, ["state_a = 1, state_b = 2"]),
      ];

      assert.deepStrictEqual(resultVDom, expectedVdom);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([[cid, entry]]),
      );
    });

    it("with state, component hasn't been initialized yet", () => {
      const module = Type.alias(
        "Hologram.Test.Fixtures.Template.Renderer.Module3",
      );
      const node = Type.tuple([
        Type.atom("component"),
        module,
        Type.list([
          Type.tuple([
            Type.bitstring("cid"),
            Type.keywordList([[Type.atom("text"), cid]]),
          ]),
        ]),
        Type.list(),
      ]);

      const resultVDom = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expectedVdom = [
        vnode("div", {attrs: {}, on: {}}, ["state_a = 11, state_b = 22"]),
      ];

      assert.deepStrictEqual(resultVDom, expectedVdom);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([
          [
            cid,
            componentRegistryEntryFixture({
              module: module,
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
        Type.list(),
      ]);

      const entry = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module4"),
        state: Type.map([
          [Type.atom("a"), Type.bitstring("state_a")],
          [Type.atom("b"), Type.bitstring("state_b")],
        ]),
      });

      ComponentRegistry.putEntry(cid, entry);

      const resultVDom = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expectedVdom = [
        vnode("div", {attrs: {}, on: {}}, [
          "var_a = state_a, var_b = state_b, var_c = prop_c",
        ]),
      ];

      assert.deepStrictEqual(resultVDom, expectedVdom);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([[cid, entry]]),
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
        Type.list(),
      ]);

      initComponentRegistryEntry(
        cid,
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module16"),
      );

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected =
        'component vars = %{cid: "my_component", prop_1: "value_1", prop_2: 2, prop_3: "aaa2bbb"}';

      assert.equal(result, expected);
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
        Type.list(),
      ]);

      const entry = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module18"),
        state: Type.map([[Type.atom("b"), Type.integer(222)]]),
      });

      ComponentRegistry.putEntry(cid, entry);

      const expectedMessage = buildKeyErrorMsg(
        Type.atom("c"),
        Type.map([
          [Type.atom("a"), Type.bitstring("111")],
          [Type.atom("b"), Type.integer(222)],
          [Type.atom("cid"), Type.bitstring("my_component")],
        ]),
      );

      assertBoxedError(
        () =>
          Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          ),
        "KeyError",
        expectedMessage,
      );
    });
  });

  // A stateful component's identity is {module, cid}, so a cid rendered by a different module than
  // the registered one is a different component - it must not inherit the previous module's state.
  describe("module swap under a cid", () => {
    const module3 = Type.alias(
      "Hologram.Test.Fixtures.Template.Renderer.Module3",
    );
    const module4 = Type.alias(
      "Hologram.Test.Fixtures.Template.Renderer.Module4",
    );

    const componentNode = (module) =>
      Type.tuple([
        Type.atom("component"),
        module,
        Type.list([
          Type.tuple([
            Type.bitstring("cid"),
            Type.keywordList([[Type.atom("text"), cid]]),
          ]),
        ]),
        Type.list(),
      ]);

    const registeredState = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    it("different module under the same cid re-initializes the component", () => {
      ComponentRegistry.putEntry(
        cid,
        componentRegistryEntryFixture({
          module: module4,
          state: registeredState,
        }),
      );

      const resultVdom = Renderer.renderDom(
        componentNode(module3),
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      // Module3's init/2 puts %{a: 11, b: 22}, so the state of the swapped-out module is gone.
      assert.deepStrictEqual(resultVdom, [
        vnode("div", {attrs: {}, on: {}}, ["state_a = 11, state_b = 22"]),
      ]);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([
          [
            cid,
            componentRegistryEntryFixture({
              module: module3,
              state: Type.map([
                [Type.atom("a"), Type.integer(11)],
                [Type.atom("b"), Type.integer(22)],
              ]),
            }),
          ],
        ]),
      );
    });

    it("same module under the same cid keeps the state", () => {
      const entry = componentRegistryEntryFixture({
        module: module3,
        state: registeredState,
      });

      ComponentRegistry.putEntry(cid, entry);

      const resultVdom = Renderer.renderDom(
        componentNode(module3),
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(resultVdom, [
        vnode("div", {attrs: {}, on: {}}, ["state_a = 1, state_b = 2"]),
      ]);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([[cid, entry]]),
      );
    });

    it("different module under the same cid re-emits the context of the new module", () => {
      ComponentRegistry.putEntry(
        cid,
        componentRegistryEntryFixture({
          module: module4,
          emittedContext: Type.map([
            [Type.atom("my_key"), Type.bitstring("swapped_out_value")],
          ]),
          state: registeredState,
        }),
      );

      Renderer.renderDom(
        componentNode(module3),
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(
        ComponentRegistry.getComponentEmittedContext(cid),
        Type.map(),
      );
    });

    it("a dynamic tag swapping the module under a cid re-initializes the component", () => {
      ComponentRegistry.putEntry(
        cid,
        componentRegistryEntryFixture({
          module: module4,
          state: registeredState,
        }),
      );

      const node = Type.tuple([
        Type.atom("dynamic_tag"),
        Type.tuple([module3]),
        Type.list([
          Type.tuple([
            Type.bitstring("cid"),
            Type.keywordList([[Type.atom("text"), cid]]),
          ]),
        ]),
        Type.list(),
      ]);

      const resultVdom = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(resultVdom, [
        vnode("div", {attrs: {}, on: {}}, ["state_a = 11, state_b = 22"]),
      ]);

      assert.deepStrictEqual(
        ComponentRegistry.getComponentModule(cid),
        module3,
      );
    });
  });

  describe("default slot", () => {
    it("with single node", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module8"),
        Type.list(),
        Type.keywordList([[Type.atom("text"), Type.bitstring("123")]]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, ["abc123xyz"]);
    });

    it("with multiple nodes", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module8"),
        Type.list(),
        Type.keywordList([
          [Type.atom("text"), Type.bitstring("123")],
          [Type.atom("expression"), Type.tuple([Type.integer(456)])],
        ]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, ["abc123456xyz"]);
    });

    it("nested components with slots, no slot tag in the top component template, not using vars", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module8"),
        Type.list(),
        Type.list([
          Type.tuple([
            Type.atom("component"),
            Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module9"),
            Type.list(),
            Type.keywordList([[Type.atom("text"), Type.bitstring("789")]]),
          ]),
        ]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

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
        Type.list(),
      ]);

      const entry10 = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module10"),
        state: Type.map([[Type.atom("a"), Type.integer(10)]]),
      });

      ComponentRegistry.putEntry(cid10, entry10);

      const entry11 = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module11"),
        state: Type.map([[Type.atom("a"), Type.integer(11)]]),
      });

      ComponentRegistry.putEntry(cid11, entry11);

      const entry12 = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module12"),
        state: Type.map([[Type.atom("a"), Type.integer(12)]]),
      });

      ComponentRegistry.putEntry(cid12, entry12);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, ["10,11,10,12,10"]);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([
          [cid10, entry10],
          [cid11, entry11],
          [cid12, entry12],
        ]),
      );
    });

    it("nested components with slots, slot tag in the top component template, not using vars", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module31"),
        Type.list(),
        Type.keywordList([[Type.atom("text"), Type.bitstring("abc")]]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

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

      const entry34 = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module34"),
        state: Type.map([
          [Type.atom("cid"), cid34],
          [Type.atom("a"), Type.bitstring("34a_prop")],
          [Type.atom("b"), Type.bitstring("34b_state")],
          [Type.atom("c"), Type.bitstring("34c_state")],
          [Type.atom("x"), Type.bitstring("34x_state")],
          [Type.atom("y"), Type.bitstring("34y_state")],
          [Type.atom("z"), Type.bitstring("34z_state")],
        ]),
      });

      ComponentRegistry.putEntry(cid34, entry34);

      const entry35 = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module35"),
        state: Type.map([
          [Type.atom("cid"), cid35],
          [Type.atom("a"), Type.bitstring("35a_prop")],
          [Type.atom("z"), Type.bitstring("35z_state")],
        ]),
      });

      ComponentRegistry.putEntry(cid35, entry35);

      const entry36 = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module36"),
        state: Type.map([
          [Type.atom("cid"), cid36],
          [Type.atom("a"), Type.bitstring("36a_prop")],
          [Type.atom("z"), Type.bitstring("36z_state")],
        ]),
      });

      ComponentRegistry.putEntry(cid36, entry36);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, [
        "34a_prop,35a_prop,34b_state,36a_prop,34c_state,abc,34x_state,36z_state,34y_state,35z_state,34z_state",
      ]);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([
          [cid34, entry34],
          [cid35, entry35],
          [cid36, entry36],
        ]),
      );
    });

    it("with nested nil node resulting from if block", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module67"),
        Type.list(),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, ["\n  \n"]);
    });
  });

  describe("dynamic tag node, element branch", () => {
    const dynamicTag = (
      value,
      attrsDom = Type.list(),
      childrenDom = Type.list(),
    ) =>
      Type.tuple([
        Type.atom("dynamic_tag"),
        Type.tuple([value]),
        attrsDom,
        childrenDom,
      ]);

    const render = (node) =>
      Renderer.renderDom(node, context, slots, defaultTarget, parentTagName);

    it("without attributes or children", () => {
      // <{"div"}></{"div"}>
      const result = render(dynamicTag(Type.bitstring("div")));

      assert.deepStrictEqual(result, vnode("div", {attrs: {}, on: {}}, []));
    });

    it("with attributes", () => {
      const attrsDom = Type.list([
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
      ]);

      const result = render(dynamicTag(Type.bitstring("div"), attrsDom));

      assert.deepStrictEqual(
        result,
        vnode("div", {attrs: {attr_1: "aaa", attr_2: "123"}, on: {}}, []),
      );
    });

    it("with children", () => {
      const childrenDom = Type.list([
        Type.tuple([
          Type.atom("element"),
          Type.bitstring("span"),
          Type.list(),
          Type.list([Type.tuple([Type.atom("text"), Type.bitstring("abc")])]),
        ]),
        Type.tuple([Type.atom("text"), Type.bitstring("xyz")]),
      ]);

      const result = render(
        dynamicTag(Type.bitstring("div"), Type.list(), childrenDom),
      );

      assert.deepStrictEqual(
        result,
        vnode("div", {attrs: {}, on: {}}, [
          vnode("span", {attrs: {}, on: {}}, ["abc"]),
          "xyz",
        ]),
      );
    });

    it("void element", () => {
      const attrsDom = Type.list([
        Type.tuple([
          Type.bitstring("attr_1"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("aaa")]]),
        ]),
      ]);

      const result = render(dynamicTag(Type.bitstring("img"), attrsDom));

      assert.deepStrictEqual(
        result,
        vnode("img", {attrs: {attr_1: "aaa"}, on: {}}, []),
      );
    });

    it("custom element", () => {
      const childrenDom = Type.list([
        Type.tuple([Type.atom("text"), Type.bitstring("abc")]),
      ]);

      const result = render(
        dynamicTag(Type.bitstring("my-widget"), Type.list(), childrenDom),
      );

      assert.deepStrictEqual(
        result,
        vnode("my-widget", {attrs: {}, on: {}}, ["abc"]),
      );
    });

    it("cid attribute is rendered as a plain HTML attribute", () => {
      const attrsDom = Type.list([
        Type.tuple([
          Type.bitstring("cid"),
          Type.keywordList([
            [Type.atom("text"), Type.bitstring("my_component")],
          ]),
        ]),
      ]);

      const result = render(dynamicTag(Type.bitstring("div"), attrsDom));

      assert.deepStrictEqual(
        result,
        vnode("div", {attrs: {cid: "my_component"}, on: {}}, []),
      );
    });

    it("event attribute binds an event listener", () => {
      const actionSpecDom = Type.list([
        Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
      ]);

      const attrsDom = Type.list([
        Type.tuple([Type.bitstring("$click"), actionSpecDom]),
      ]);

      const result = render(dynamicTag(Type.bitstring("button"), attrsDom));

      assert.deepStrictEqual(Object.keys(result.data.on), ["click"]);

      const stub = sinon
        .stub(Hologram, "handleUiEvent")
        .callsFake(
          (_event, _eventType, _operationSpecVdom, _defaultTarget) => null,
        );

      result.data.on.click("dummyEvent");

      sinon.assert.calledWith(
        stub,
        "dummyEvent",
        "click",
        actionSpecDom,
        defaultTarget,
      );

      Hologram.handleUiEvent.restore();
    });

    it("with spread", () => {
      const attrsDom = Type.list([
        Type.tuple([
          Type.atom("spread"),
          Type.tuple([
            Type.map([
              [Type.atom("id"), Type.bitstring("my_id")],
              [Type.atom("class"), Type.bitstring("my_class")],
            ]),
          ]),
        ]),
      ]);

      const result = render(dynamicTag(Type.bitstring("div"), attrsDom));

      assert.deepStrictEqual(
        result,
        vnode("div", {attrs: {class: "my_class", id: "my_id"}, on: {}}, []),
      );
    });

    it("with nested stateful component", () => {
      const childrenDom = Type.list([
        Type.tuple([
          Type.atom("component"),
          Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module1"),
          Type.list([
            Type.tuple([
              Type.bitstring("cid"),
              Type.keywordList([[Type.atom("text"), cid]]),
            ]),
          ]),
          Type.list(),
        ]),
      ]);

      initComponentRegistryEntry(
        cid,
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module1"),
      );

      const result = render(
        dynamicTag(Type.bitstring("div"), Type.list(), childrenDom),
      );

      assert.deepStrictEqual(
        result,
        vnode("div", {attrs: {}, on: {}}, [
          vnode("div", {attrs: {}, on: {}}, ["abc"]),
        ]),
      );

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([
          [
            cid,
            componentRegistryEntryFixture({
              module: Type.alias(
                "Hologram.Test.Fixtures.Template.Renderer.Module1",
              ),
            }),
          ],
        ]),
      );
    });

    it("tag name with uppercase chars", () => {
      // <{"DIV"}></{"DIV"}>
      const result = render(dynamicTag(Type.bitstring("DIV")));

      assert.deepStrictEqual(result, vnode("div", {attrs: {}, on: {}}, []));
    });

    it("SVG tag name that lost its case", () => {
      // <{"lineargradient"}></{"lineargradient"}>
      const result = render(dynamicTag(Type.bitstring("lineargradient")));

      assert.deepStrictEqual(
        result,
        vnode("linearGradient", {attrs: {}, on: {}}, []),
      );
    });

    it("SVG tag name that is already spelled the way the parser spells it", () => {
      // <{"linearGradient"}></{"linearGradient"}>
      const result = render(dynamicTag(Type.bitstring("linearGradient")));

      assert.deepStrictEqual(
        result,
        vnode("linearGradient", {attrs: {}, on: {}}, []),
      );
    });

    it("tag name that names an Object.prototype member", () => {
      // <{"constructor"}></{"constructor"}>
      const result = render(dynamicTag(Type.bitstring("constructor")));

      assert.deepStrictEqual(
        result,
        vnode("constructor", {attrs: {}, on: {}}, []),
      );
    });
  });

  describe("dynamic tag node, component branch", () => {
    const dynamicTag = (
      value,
      attrsDom = Type.list(),
      childrenDom = Type.list(),
    ) =>
      Type.tuple([
        Type.atom("dynamic_tag"),
        Type.tuple([value]),
        attrsDom,
        childrenDom,
      ]);

    const render = (node) =>
      Renderer.renderDom(node, context, slots, defaultTarget, parentTagName);

    it("stateless component without props", () => {
      // <{Module1} />
      const result = render(
        dynamicTag(
          Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module1"),
        ),
      );

      assert.deepStrictEqual(result, [
        vnode("div", {attrs: {}, on: {}}, ["abc"]),
      ]);
      assert.deepStrictEqual(ComponentRegistry.entries, Type.map());
    });

    it("stateless component with props", () => {
      const propsDom = Type.list([
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
      ]);

      const result = render(
        dynamicTag(
          Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module2"),
          propsDom,
        ),
      );

      assert.deepStrictEqual(result, [
        vnode("div", {attrs: {}, on: {}}, [
          "prop_a = ddd, prop_b = 222, prop_c = fff333hhh",
        ]),
      ]);
    });

    it("stateful component", () => {
      const propsDom = Type.list([
        Type.tuple([
          Type.bitstring("cid"),
          Type.keywordList([[Type.atom("text"), cid]]),
        ]),
      ]);

      initComponentRegistryEntry(
        cid,
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module1"),
      );

      const result = render(
        dynamicTag(
          Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module1"),
          propsDom,
        ),
      );

      assert.deepStrictEqual(result, [
        vnode("div", {attrs: {}, on: {}}, ["abc"]),
      ]);

      assert.deepStrictEqual(
        ComponentRegistry.entries,
        Type.map([
          [
            cid,
            componentRegistryEntryFixture({
              module: Type.alias(
                "Hologram.Test.Fixtures.Template.Renderer.Module1",
              ),
            }),
          ],
        ]),
      );
    });

    it("undeclared props are dropped", () => {
      const propsDom = Type.list([
        Type.tuple([
          Type.bitstring("my_undeclared_prop"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("my_value")]]),
        ]),
      ]);

      const result = render(
        dynamicTag(
          Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module1"),
          propsDom,
        ),
      );

      assert.deepStrictEqual(result, [
        vnode("div", {attrs: {}, on: {}}, ["abc"]),
      ]);
    });

    it("event attributes are not passed as props", () => {
      const propsDom = Type.list([
        Type.tuple([
          Type.bitstring("$click"),
          Type.keywordList([[Type.atom("text"), Type.bitstring("my_action")]]),
        ]),
      ]);

      const node = dynamicTag(
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module2"),
        propsDom,
      );

      assertBoxedError(
        () => render(node),
        "KeyError",
        buildKeyErrorMsg(Type.atom("a"), Type.map()),
      );
    });

    it("with slot content", () => {
      const childrenDom = Type.keywordList([
        [Type.atom("text"), Type.bitstring("123")],
      ]);

      const result = render(
        dynamicTag(
          Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module8"),
          Type.list(),
          childrenDom,
        ),
      );

      assert.deepStrictEqual(result, ["abc123xyz"]);
    });

    it("with prop spread", () => {
      const propsDom = Type.list([
        Type.tuple([
          Type.atom("spread"),
          Type.tuple([
            Type.map([
              [Type.atom("a"), Type.bitstring("ddd")],
              [Type.atom("b"), Type.integer(222)],
              [Type.atom("c"), Type.bitstring("fff")],
            ]),
          ]),
        ]),
      ]);

      const result = render(
        dynamicTag(
          Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module2"),
          propsDom,
        ),
      );

      assert.deepStrictEqual(result, [
        vnode("div", {attrs: {}, on: {}}, [
          "prop_a = ddd, prop_b = 222, prop_c = fff",
        ]),
      ]);
    });
  });

  describe("dynamic tag node, slots", () => {
    it("slot content is expanded through dynamic tag children", () => {
      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module87"),
        Type.list(),
        Type.keywordList([[Type.atom("text"), Type.bitstring("abc")]]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, [
        "87a,32a,87b,",
        vnode("div", {attrs: {}, on: {}}, ["abc"]),
        ",87x,32z,87z",
      ]);
    });
  });

  describe("dynamic tag node, invalid tag name value", () => {
    const render = (value) =>
      Renderer.renderDom(
        Type.tuple([
          Type.atom("dynamic_tag"),
          Type.tuple([value]),
          Type.list(),
          Type.list(),
        ]),
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

    const assertNotAComponent = (value, inspectedValue) =>
      assertBoxedError(
        () => render(value),
        "ArgumentError",
        `dynamic tag expression must evaluate to a component module or an HTML tag name string, got: ${inspectedValue}, which is not a component module`,
      );

    it("non-component atom", () => {
      assertNotAComponent(Type.atom("div"), ":div");
    });

    it("page module", () => {
      assertNotAComponent(
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module14"),
        "Hologram.Test.Fixtures.Template.Renderer.Module14",
      );
    });

    it("nil", () => {
      assertNotAComponent(Type.nil(), "nil");
    });

    it("integer", () => {
      assertBoxedError(
        () => render(Type.integer(123)),
        "ArgumentError",
        "dynamic tag expression must evaluate to a component module or an HTML tag name string, got: 123",
      );
    });

    it("non-binary bitstring", () => {
      assertBoxedError(
        () => render(Type.bitstring([1, 1])),
        "ArgumentError",
        "dynamic tag expression must evaluate to a component module or an HTML tag name string, got: <<3::size(2)>>",
      );
    });

    it("map", () => {
      assertBoxedError(
        () => render(Type.map([[Type.atom("a"), Type.integer(1)]])),
        "ArgumentError",
        "dynamic tag expression must evaluate to a component module or an HTML tag name string, got: %{a: 1}",
      );
    });

    it("component module missing from the page bundle", () => {
      assert.throw(
        () =>
          render(
            Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module999"),
          ),
        HologramRuntimeError,
        "module Hologram.Test.Fixtures.Template.Renderer.Module999 is not available on the client, because it was not reachable from client code at compile time",
      );
    });
  });

  describe("window node", () => {
    beforeEach(() => {
      Renderer.listenerBindings = [];
    });

    // The once tests below mark the real window, which is never collected, so the fired-state would
    // otherwise persist into later tests. Reset it after each so the suite stays order-independent.
    afterEach(() => {
      Once.reset();
    });

    it("renders nil and collects the binding scoped to the enclosing component", () => {
      // <window $key_down="my_action" />
      const actionSpecDom = Type.list([
        Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
      ]);

      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("window"),
        Type.list([Type.tuple([Type.bitstring("$key_down"), actionSpecDom])]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, Type.nil());
      assert.equal(Renderer.listenerBindings.length, 1);
      assert.equal(Renderer.listenerBindings[0].key, "bubble:keydown");
      assert.equal(Renderer.listenerBindings[0].target, window);

      const stub = sinon
        .stub(Hologram, "handleUiEvent")
        .callsFake(
          (_event, _eventType, _operationSpecVdom, _defaultTarget) => null,
        );

      Renderer.listenerBindings[0].handler("dummyEvent");

      sinon.assert.calledWith(
        stub,
        "dummyEvent",
        "keydown",
        actionSpecDom,
        defaultTarget,
      );

      Hologram.handleUiEvent.restore();
    });

    it("collects a binding per window event", () => {
      // <window $key_down="my_down_action" $key_up="my_up_action" />
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("window"),
        Type.list([
          Type.tuple([
            Type.bitstring("$key_down"),
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("my_down_action")]),
            ]),
          ]),
          Type.tuple([
            Type.bitstring("$key_up"),
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("my_up_action")]),
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      Renderer.renderDom(node, context, slots, defaultTarget, parentTagName);

      assert.deepStrictEqual(
        Renderer.listenerBindings.map((binding) => binding.key),
        ["bubble:keydown", "bubble:keyup"],
      );
    });

    it("collects nothing for a bare window tag", () => {
      // <window />
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("window"),
        Type.list(),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, Type.nil());
      assert.equal(Renderer.listenerBindings.length, 0);
    });

    it("drops a binding whose once modifier has fired", () => {
      // <window $key_down.once="my_action" />
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("window"),
        Type.list([
          Type.tuple([
            Type.bitstring("$key_down"),
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
            ]),
            Type.map([[Type.atom("once"), Type.boolean(true)]]),
          ]),
        ]),
        Type.list(),
      ]);

      Renderer.renderDom(node, context, slots, defaultTarget, parentTagName);

      // Before firing, the binding resolves into the desired set.
      assert.equal(Renderer.resolveListenerBindings().length, 1);

      // A window binding keys once on the window target and its push position.
      const {target, slotKey} = Renderer.listenerBindings[0];
      Once.markFired(target, slotKey);

      // Now it is dropped, so reconcile detaches its real listener.
      assert.equal(Renderer.resolveListenerBindings().length, 0);
    });

    it("keeps a non-once binding that reuses a spent once binding's slot", () => {
      // A listener slot is positional across a render's listener bindings, so when the binding set
      // changes a non-once binding can inherit the slot a spent once binding held. A throwaway
      // stand-in for the shared window/document target keeps this fired-state from leaking to other
      // tests; a prior render's spent once binding marked this (target, slot).
      const target = {};
      Once.markFired(target, 0);

      // This render, a non-once binding takes the same slot on the same target. The drop is gated on
      // the binding's own once flag, so the inherited fired-state must not suppress it.
      Renderer.listenerBindings = [
        {
          target,
          key: "bubble:keyup",
          attach: () => {},
          handler: () => {},
          slotKey: 0,
          once: false,
        },
      ];

      assert.equal(Renderer.resolveListenerBindings().length, 1);
    });
  });

  describe("document node", () => {
    beforeEach(() => {
      Renderer.listenerBindings = [];
    });

    it("renders nil and collects the binding with the document target", () => {
      // <document $key_down="my_action" />
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("document"),
        Type.list([
          Type.tuple([
            Type.bitstring("$key_down"),
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, Type.nil());
      assert.equal(Renderer.listenerBindings.length, 1);
      assert.equal(Renderer.listenerBindings[0].key, "bubble:keydown");
      assert.equal(Renderer.listenerBindings[0].target, document);
    });
  });

  describe("click_outside binding", () => {
    const actionSpecDom = Type.list([
      Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
    ]);

    const clickOutsideElement = (specDom, children = Type.list()) =>
      Type.tuple([
        Type.atom("element"),
        Type.bitstring("div"),
        Type.list([Type.tuple([Type.bitstring("$click_outside"), specDom])]),
        children,
      ]);

    beforeEach(() => {
      Renderer.listenerBindings = [];
    });

    it("attaches no per-element listener and collects a document-level click binding", () => {
      // <div $click_outside="my_action"></div>
      const vdom = Renderer.renderDom(
        clickOutsideElement(actionSpecDom),
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(vdom.data.on, {});

      assert.equal(Renderer.listenerBindings.length, 1);
      assert.equal(Renderer.listenerBindings[0].target, document);

      // Capture phase (key prefix) so the opening click - which renders the element synchronously,
      // mid-bubble - is not seen as an outside click by the listener it installs.
      assert.equal(Renderer.listenerBindings[0].key, "capture:click");
    });

    it("dispatches only when the click lands outside the bound element", () => {
      const vdom = Renderer.renderDom(
        clickOutsideElement(actionSpecDom),
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      // Snabbdom sets `.elm` during patch; emulate the bound element's containment here.
      const insideTarget = {};
      const outsideTarget = {};
      vdom.elm = {contains: (target) => target === insideTarget};

      const stub = sinon
        .stub(Hologram, "handleUiEvent")
        .callsFake(
          (_event, _eventType, _operationSpecVdom, _defaultTarget) => null,
        );

      const handler = Renderer.listenerBindings[0].handler;

      handler({target: insideTarget});
      sinon.assert.notCalled(stub);

      const outsideEvent = {target: outsideTarget};
      handler(outsideEvent);

      sinon.assert.calledOnceWithExactly(
        stub,
        outsideEvent,
        "click_outside",
        actionSpecDom,
        defaultTarget,
      );

      Hologram.handleUiEvent.restore();
    });

    it("nested bindings each gate on their own subtree", () => {
      // <div $click_outside="outer_action"><div $click_outside="inner_action"></div></div>
      const outerSpecDom = Type.list([
        Type.tuple([Type.atom("text"), Type.bitstring("outer_action")]),
      ]);

      const innerSpecDom = Type.list([
        Type.tuple([Type.atom("text"), Type.bitstring("inner_action")]),
      ]);

      const outerVdom = Renderer.renderDom(
        clickOutsideElement(
          outerSpecDom,
          Type.list([clickOutsideElement(innerSpecDom)]),
        ),
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const innerVdom = outerVdom.children[0];

      // A click inside the outer element but outside the inner one.
      outerVdom.elm = {contains: () => true};
      innerVdom.elm = {contains: () => false};

      const stub = sinon
        .stub(Hologram, "handleUiEvent")
        .callsFake(
          (_event, _eventType, _operationSpecVdom, _defaultTarget) => null,
        );

      const event = {target: {}};
      Renderer.listenerBindings.forEach((binding) => binding.handler(event));

      // Only the inner binding (whose subtree excludes the target) dispatches.
      sinon.assert.calledOnceWithExactly(
        stub,
        event,
        "click_outside",
        innerSpecDom,
        defaultTarget,
      );

      Hologram.handleUiEvent.restore();
    });

    it("with a once modifier fires once across repeated outside clicks, then re-arms on a re-created element", () => {
      // <div $click_outside.once="my_action"></div>
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("div"),
        Type.list([
          Type.tuple([
            Type.bitstring("$click_outside"),
            actionSpecDom,
            Type.map([[Type.atom("once"), Type.boolean(true)]]),
          ]),
        ]),
        Type.list(),
      ]);

      const vdom = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      // Every click lands outside the bound element. once keys on the element, read live from `.elm`.
      vdom.elm = {contains: () => false};

      const dispatch = sinon.spy();
      sinon.stub(Hologram, "handleUiEvent").returns(dispatch);

      const handler = Renderer.listenerBindings[0].handler;

      handler({target: {}});
      handler({target: {}});
      handler({target: {}});

      // Spent after the first outside click; later ones are no-ops.
      sinon.assert.calledOnce(dispatch);

      // A re-created element is a new node with no fired-state, so the binding re-arms.
      vdom.elm = {contains: () => false};
      handler({target: {}});

      sinon.assert.calledTwice(dispatch);

      Hologram.handleUiEvent.restore();
    });
  });

  describe("reach binding", () => {
    const actionSpecDom = Type.list([
      Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
    ]);

    const reachElement = (attrName, specDom) =>
      Type.tuple([
        Type.atom("element"),
        Type.bitstring("div"),
        Type.list([Type.tuple([Type.bitstring(attrName), specDom])]),
        Type.list(),
      ]);

    beforeEach(() => {
      Renderer.listenerBindings = [];
      Renderer.reachBindings = [];
    });

    it("adds no per-element listener and collects a deferred binding carrying the vnode and edge", () => {
      // <div $reach_bottom="my_action"></div>
      const vdom = Renderer.renderDom(
        reachElement("$reach_bottom", actionSpecDom),
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      // A reach is delivered by a scroll listener, so nothing is added to the element's "on" map.
      assert.deepStrictEqual(vdom.data.on, {});

      assert.equal(Renderer.reachBindings.length, 1);
      assert.equal(Renderer.reachBindings[0].vnode, vdom);
      assert.equal(Renderer.reachBindings[0].edge, "bottom");
    });

    it("dispatches the event through the bound element's handler under the edge-typed event", () => {
      Renderer.renderDom(
        reachElement("$reach_bottom", actionSpecDom),
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const stub = sinon
        .stub(Hologram, "handleUiEvent")
        .callsFake(
          (_event, _eventType, _operationSpecVdom, _defaultTarget) => null,
        );

      const event = {target: {}};

      Renderer.reachBindings[0].handler(event);

      sinon.assert.calledOnceWithExactly(
        stub,
        event,
        "reach_bottom",
        actionSpecDom,
        defaultTarget,
        false,
        false,
        false,
      );

      Hologram.handleUiEvent.restore();
    });

    it("resolves into a registry binding targeting the container", () => {
      const vdom = Renderer.renderDom(
        reachElement("$reach_bottom", actionSpecDom),
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      // Snabbdom sets `.elm` during patch; emulate the container here.
      const container = {};
      vdom.elm = container;

      const resolved = Renderer.resolveReachBindings();

      assert.equal(resolved.length, 1);
      assert.equal(resolved[0].target, container);
      assert.equal(resolved[0].key, "scroll-edge:bottom:100%");
      assert.equal(resolved[0].handler, Renderer.reachBindings[0].handler);
      assert.isFunction(resolved[0].attach);
    });

    it("threads the within modifier's distance into the scroll-edge listener", () => {
      // <div $reach_bottom.within(200px)="my_action"></div>
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("div"),
        Type.list([
          Type.tuple([
            Type.bitstring("$reach_bottom"),
            actionSpecDom,
            Type.map([[Type.atom("within"), Type.bitstring("200px")]]),
          ]),
        ]),
        Type.list(),
      ]);

      const vdom = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const container = {};
      vdom.elm = container;

      const stub = sinon
        .stub(EventListeners, "scrollEdge")
        .returns({key: "scroll-edge:bottom", attach: () => {}});

      try {
        Renderer.resolveReachBindings();
      } finally {
        EventListeners.scrollEdge.restore();
      }

      sinon.assert.calledOnceWithExactly(stub, container, "bottom", "200px");
    });

    it("drops a binding whose once modifier has fired, then re-arms on a re-created element", () => {
      // <div $reach_bottom.once="my_action"></div>
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("div"),
        Type.list([
          Type.tuple([
            Type.bitstring("$reach_bottom"),
            actionSpecDom,
            Type.map([[Type.atom("once"), Type.boolean(true)]]),
          ]),
        ]),
        Type.list(),
      ]);

      const vdom = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const container = {};
      vdom.elm = container;

      // Before firing, the binding resolves into the desired set.
      assert.equal(Renderer.resolveReachBindings().length, 1);

      // The reach handler keys once on the dispatched event's target, the container.
      Once.markFired(container, 0);

      // Now it is dropped, so reconcile detaches its scroll listener.
      assert.equal(Renderer.resolveReachBindings().length, 0);

      // A re-created element is a new node with no fired-state, so the binding re-arms.
      vdom.elm = {};
      assert.equal(Renderer.resolveReachBindings().length, 1);
    });
  });

  describe("resize binding", () => {
    const actionSpecDom = Type.list([
      Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
    ]);

    const resizeElement = (specDom) =>
      Type.tuple([
        Type.atom("element"),
        Type.bitstring("div"),
        Type.list([Type.tuple([Type.bitstring("$resize"), specDom])]),
        Type.list(),
      ]);

    beforeEach(() => {
      Renderer.listenerBindings = [];
      Renderer.resizeBindings = [];
    });

    it("adds no per-element listener and collects a deferred binding carrying the vnode", () => {
      // <div $resize="my_action"></div>
      const vdom = Renderer.renderDom(
        resizeElement(actionSpecDom),
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      // Element resize rides a ResizeObserver, so nothing is added to the element's "on" map.
      assert.deepStrictEqual(vdom.data.on, {});

      assert.equal(Renderer.resizeBindings.length, 1);
      assert.equal(Renderer.resizeBindings[0].vnode, vdom);
    });

    it("dispatches the observer entry through the bound element's handler", () => {
      Renderer.renderDom(
        resizeElement(actionSpecDom),
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const stub = sinon
        .stub(Hologram, "handleUiEvent")
        .callsFake(
          (_event, _eventType, _operationSpecVdom, _defaultTarget) => null,
        );

      const entry = {
        target: {},
        borderBoxSize: [{blockSize: 10, inlineSize: 20}],
      };

      Renderer.resizeBindings[0].handler(entry);

      sinon.assert.calledOnceWithExactly(
        stub,
        entry,
        "resize",
        actionSpecDom,
        defaultTarget,
        false,
        false,
        false,
      );

      Hologram.handleUiEvent.restore();
    });

    it("resolves deferred bindings into observer registry bindings after patch", () => {
      const vdom = Renderer.renderDom(
        resizeElement(actionSpecDom),
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      // Snabbdom sets `.elm` during patch; emulate the bound element here.
      const element = {};
      vdom.elm = element;

      const originalResizeObserver = globalThis.ResizeObserver;
      globalThis.ResizeObserver = class {
        observe() {}
        disconnect() {}
      };

      let resolved;

      try {
        resolved = Renderer.resolveResizeBindings();
      } finally {
        globalThis.ResizeObserver = originalResizeObserver;
      }

      assert.equal(resolved.length, 1);
      assert.equal(resolved[0].target, element);
      assert.equal(resolved[0].key, "resize-observer");
      assert.equal(resolved[0].handler, Renderer.resizeBindings[0].handler);
      assert.isFunction(resolved[0].attach);
    });

    it("drops a binding whose once modifier has fired", () => {
      // <div $resize.once="my_action"></div>
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("div"),
        Type.list([
          Type.tuple([
            Type.bitstring("$resize"),
            actionSpecDom,
            Type.map([[Type.atom("once"), Type.boolean(true)]]),
          ]),
        ]),
        Type.list(),
      ]);

      const vdom = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const element = {};
      vdom.elm = element;

      // Before firing, the binding resolves into the desired set.
      assert.equal(Renderer.resolveResizeBindings().length, 1);

      // The resize handler keys once on the observed element.
      Once.markFired(element, 0);

      // Now it is dropped, so reconcile disconnects its observer.
      assert.equal(Renderer.resolveResizeBindings().length, 0);
    });

    it("a <window> $resize stays a DOM-event listener binding, not an observer one", () => {
      // <window $resize="my_action" />
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("window"),
        Type.list([Type.tuple([Type.bitstring("$resize"), actionSpecDom])]),
        Type.list(),
      ]);

      Renderer.renderDom(node, context, slots, defaultTarget, parentTagName);

      assert.equal(Renderer.resizeBindings.length, 0);
      assert.equal(Renderer.listenerBindings.length, 1);
      assert.equal(Renderer.listenerBindings[0].key, "bubble:resize");
      assert.equal(Renderer.listenerBindings[0].target, window);
    });
  });

  describe("context", () => {
    it("emitted in page, accessed in component nested in page", () => {
      initComponentRegistryEntry(
        Type.bitstring("layout"),
        Type.alias("Hologram.Test.Fixtures.LayoutFixture"),
      );

      const pageEntry = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module39"),
        emittedContext: Type.map([
          [
            Type.tuple([Type.atom("my_scope"), Type.atom("my_key")]),
            Type.integer(123),
          ],
        ]),
      });

      ComponentRegistry.putEntry(Type.bitstring("page"), pageEntry);

      const result = Renderer.renderPage(
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module39"),
        Type.map(),
      );

      const expected = vnode("html", {attrs: {}, on: {}}, [
        vnode("body", {attrs: {}, on: {}}, ["prop_aaa = 123"]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("emitted in page, accessed in component nested in layout", () => {
      initComponentRegistryEntry(
        Type.bitstring("layout"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module47"),
      );

      const pageEntry = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module46"),
        emittedContext: Type.map([
          [
            Type.tuple([Type.atom("my_scope"), Type.atom("my_key")]),
            Type.integer(123),
          ],
        ]),
      });

      ComponentRegistry.putEntry(Type.bitstring("page"), pageEntry);

      const result = Renderer.renderPage(
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module46"),
        Type.map(),
      );

      const expected = vnode("html", {attrs: {}, on: {}}, [
        vnode("body", {attrs: {}, on: {}}, ["prop_aaa = 123"]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("emitted in page, accessed in layout", () => {
      initComponentRegistryEntry(
        Type.bitstring("layout"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module41"),
      );

      const pageEntry = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module40"),
        emittedContext: Type.map([
          [
            Type.tuple([Type.atom("my_scope"), Type.atom("my_key")]),
            Type.integer(123),
          ],
        ]),
      });

      ComponentRegistry.putEntry(Type.bitstring("page"), pageEntry);

      const result = Renderer.renderPage(
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module40"),
        Type.map(),
      );

      const expected = vnode("html", {attrs: {}, on: {}}, [
        vnode("body", {attrs: {}, on: {}}, ["prop_aaa = 123"]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("emmited in layout, accessed in component nested in page", () => {
      initComponentRegistryEntry(
        Type.bitstring("page"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module43"),
      );

      const layoutEntry = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module42"),
        emittedContext: Type.map([
          [
            Type.tuple([Type.atom("my_scope"), Type.atom("my_key")]),
            Type.integer(123),
          ],
        ]),
      });

      ComponentRegistry.putEntry(Type.bitstring("layout"), layoutEntry);

      const result = Renderer.renderPage(
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module43"),
        Type.map(),
      );

      const expected = vnode("html", {attrs: {}, on: {}}, [
        vnode("body", {attrs: {}, on: {}}, ["prop_aaa = 123"]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("emitted in layout, accessed in component nested in layout", () => {
      initComponentRegistryEntry(
        Type.bitstring("page"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module45"),
      );

      const layoutEntry = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module44"),
        emittedContext: Type.map([
          [
            Type.tuple([Type.atom("my_scope"), Type.atom("my_key")]),
            Type.integer(123),
          ],
        ]),
      });

      ComponentRegistry.putEntry(Type.bitstring("layout"), layoutEntry);

      const result = Renderer.renderPage(
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module45"),
        Type.map(),
      );

      const expected = vnode("html", {attrs: {}, on: {}}, [
        vnode("body", {attrs: {}, on: {}}, ["prop_aaa = 123"]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("emitted in component, accessed in component", () => {
      const cid = Type.bitstring("component_37");

      const entry = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module37"),
        emittedContext: Type.map([
          [
            Type.tuple([Type.atom("my_scope"), Type.atom("my_key")]),
            Type.integer(123),
          ],
        ]),
      });

      ComponentRegistry.putEntry(cid, entry);

      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module37"),
        Type.list([
          Type.tuple([
            Type.bitstring("cid"),
            Type.keywordList([[Type.atom("text"), cid]]),
          ]),
        ]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(result, ["prop_aaa = 123"]);
    });
  });

  describe("page", () => {
    it("inside layout slot", () => {
      initComponentRegistryEntry(
        Type.bitstring("page"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module14"),
      );
      initComponentRegistryEntry(
        Type.bitstring("layout"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module15"),
      );

      const result = Renderer.renderPage(
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module14"),
        Type.map(),
      );

      const expected = vnode("html", {attrs: {}, on: {}}, [
        vnode("body", {attrs: {}, on: {}}, [
          "layout template start, page template, layout template end",
        ]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    // This test case doesn't apply to the client renderer, because the client renderer receives already cast page params.
    // it("cast page params")

    it("cast layout explicit static props", () => {
      initComponentRegistryEntry(
        Type.bitstring("page"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module25"),
      );
      initComponentRegistryEntry(
        Type.bitstring("layout"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module26"),
      );

      const result = Renderer.renderPage(
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module25"),
        Type.map(),
      );

      const expected = vnode("html", {attrs: {}, on: {}}, [
        vnode("body", {attrs: {}, on: {}}, [
          'layout vars = %{cid: "layout", prop_1: "prop_value_1", prop_3: "prop_value_3"}',
        ]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("cast layout props passed implicitely from page state", () => {
      const pageEntry = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module27"),
        state: Type.map([
          [Type.atom("prop_1"), Type.bitstring("prop_value_1")],
          [Type.atom("prop_2"), Type.bitstring("prop_value_2")],
          [Type.atom("prop_3"), Type.bitstring("prop_value_3")],
        ]),
      });

      ComponentRegistry.putEntry(Type.bitstring("page"), pageEntry);

      initComponentRegistryEntry(
        Type.bitstring("layout"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module26"),
      );

      const result = Renderer.renderPage(
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module27"),
        Type.map(),
      );

      const expected = vnode("html", {attrs: {}, on: {}}, [
        vnode("body", {attrs: {}, on: {}}, [
          'layout vars = %{cid: "layout", prop_1: "prop_value_1", prop_3: "prop_value_3"}',
        ]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("aggregate page vars, giving state vars priority over param vars when there are name conflicts", () => {
      const pageEntry = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module21"),
        state: Type.map([
          [Type.atom("key_2"), Type.bitstring("state_value_2")],
          [Type.atom("key_3"), Type.bitstring("state_value_3")],
        ]),
      });

      ComponentRegistry.putEntry(Type.bitstring("page"), pageEntry);

      initComponentRegistryEntry(
        Type.bitstring("layout"),
        Type.alias("Hologram.Test.Fixtures.LayoutFixture"),
      );

      const result = Renderer.renderPage(
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module21"),
        Type.map([
          [Type.atom("key_1"), Type.bitstring("param_value_1")],
          [Type.atom("key_2"), Type.bitstring("param_value_2")],
        ]),
      );

      const expected = vnode("html", {attrs: {}, on: {}}, [
        vnode("body", {attrs: {}, on: {}}, [
          'page vars = %{key_1: "param_value_1", key_2: "state_value_2", key_3: "state_value_3"}',
        ]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("aggregate layout vars, giving state vars priority over prop vars when there are name conflicts", () => {
      initComponentRegistryEntry(
        Type.bitstring("page"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module24"),
      );

      const layoutEntry = componentRegistryEntryFixture({
        module: Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module23"),
        state: Type.map([
          [Type.atom("key_2"), Type.bitstring("state_value_2")],
          [Type.atom("key_3"), Type.bitstring("state_value_3")],
        ]),
      });

      ComponentRegistry.putEntry(Type.bitstring("layout"), layoutEntry);

      const result = Renderer.renderPage(
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module24"),
        Type.map(),
      );

      const expected = vnode("html", {attrs: {}, on: {}}, [
        vnode("body", {attrs: {}, on: {}}, [
          'layout vars = %{cid: "layout", key_1: "prop_value_1", key_2: "state_value_2", key_3: "state_value_3"}',
        ]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("with DOCTYPE", () => {
      initComponentRegistryEntry(
        Type.bitstring("page"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module62"),
      );
      initComponentRegistryEntry(
        Type.bitstring("layout"),
        Type.alias("Hologram.Test.Fixtures.LayoutFixture"),
      );

      const result = Renderer.renderPage(
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module62"),
        Type.map(),
      );

      const expected = vnode("html", {attrs: {}, on: {}}, [
        "\n  ",
        vnode("body", {attrs: {}, on: {}}, ["\n    Module62\n  "]),
        "\n",
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("without the root <html> element", () => {
      initComponentRegistryEntry(
        Type.bitstring("page"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module63"),
      );
      initComponentRegistryEntry(
        Type.bitstring("layout"),
        Type.alias("Hologram.Test.Fixtures.LayoutFixture"),
      );

      const result = Renderer.renderPage(
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module63"),
        Type.map(),
      );

      const expected = vnode("html", {attrs: {}, on: {}}, [
        vnode("body", {attrs: {}, on: {}}, ["abc"]),
      ]);

      assert.deepStrictEqual(result, expected);
    });
  });

  // IMPORTANT!
  // Keep client-side Renderer "escaping" and server-side Renderer "escaping" unit tests consistent.
  //
  // Note: the behaviour is different on client-side vs server-side
  // because client-side escaping is delegated to Snabbdom
  describe("escaping", () => {
    const context = Type.map();
    const defaultTarget = Type.bitstring("my_target");
    const parentTagName = "div";
    const slots = Type.keywordList();

    // Note: server-side version escapes
    it("text inside non-raw-text elements", () => {
      // <div>abc < xyz</div>
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("div"),
        Type.list(),
        Type.list([
          Type.tuple([Type.atom("text"), Type.bitstring("abc < xyz")]),
        ]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode("div", {attrs: {}, on: {}}, ["abc < xyz"]);

      assert.deepStrictEqual(result, expected);
    });

    it("text inside script elements", () => {
      // <script>abc < xyz</script>
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("script"),
        Type.list(),
        Type.list([
          Type.tuple([Type.atom("text"), Type.bitstring("abc < xyz")]),
        ]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode(
        "script",
        {attrs: {}, key: "__hologramScript__:abc < xyz", on: {}},
        ["abc < xyz"],
      );

      assert.deepStrictEqual(result, expected);
    });

    // The client never escapes plain text - it sets it through the DOM, where nothing decodes.
    // A style element carries no resource key, unlike a script.
    it("text inside style elements", () => {
      // <style>a > b & c</style>
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("style"),
        Type.list(),
        Type.list([
          Type.tuple([Type.atom("text"), Type.bitstring("a > b & c")]),
        ]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode("style", {attrs: {}, on: {}}, ["a > b & c"]);

      assert.deepStrictEqual(result, expected);
    });

    // Note: server-side version escapes
    it("text inside public comments", () => {
      // <!-- abc < xyz -->
      const node = Type.tuple([
        Type.atom("public_comment"),
        Type.list([
          Type.tuple([Type.atom("text"), Type.bitstring(" abc < xyz ")]),
        ]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode("!", " abc < xyz ");

      assert.deepStrictEqual(result, expected);
    });

    // Note: server-side version escapes
    it("text inside attribute", () => {
      // <div class="abc < xyz"></div>
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("div"),
        Type.list([
          Type.tuple([
            Type.bitstring("class"),
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("abc < xyz")]),
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode("div", {attrs: {class: "abc < xyz"}, on: {}}, []);

      assert.deepStrictEqual(result, expected);
    });

    // Note: server-side version escapes
    it("expression inside non-raw-text elements", () => {
      // <div>{"abc < xyz"}</div>
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("div"),
        Type.list(),
        Type.list([
          Type.tuple([
            Type.atom("expression"),
            Type.tuple([Type.bitstring("abc < xyz")]),
          ]),
        ]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode("div", {attrs: {}, on: {}}, ["abc < xyz"]);

      assert.deepStrictEqual(result, expected);
    });

    // Note: escaped the same way on the server
    it("expression inside script elements", () => {
      // <script>{"abc < xyz"}</script>
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("script"),
        Type.list(),
        Type.list([
          Type.tuple([
            Type.atom("expression"),
            Type.tuple([Type.bitstring("abc < xyz")]),
          ]),
        ]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode(
        "script",
        {attrs: {}, key: "__hologramScript__:abc \\u{3C} xyz", on: {}},
        ["abc \\u{3C} xyz"],
      );

      assert.deepStrictEqual(result, expected);
    });

    // The text an expression contributes to a script element, as rendered by the client.
    const scriptExpressionText = (text) => {
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("script"),
        Type.list(),
        Type.list([
          Type.tuple([
            Type.atom("expression"),
            Type.tuple([Type.bitstring(text)]),
          ]),
        ]),
      ]);

      return Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      ).children[0].text;
    };

    it("expression inside script elements, backslash char", () => {
      assert.equal(scriptExpressionText("\\"), "\\\\");
    });

    it("expression inside script elements, double quote char", () => {
      assert.equal(scriptExpressionText('"'), '\\"');
    });

    it("expression inside script elements, single quote char", () => {
      assert.equal(scriptExpressionText("'"), "\\'");
    });

    it("expression inside script elements, backtick char", () => {
      assert.equal(scriptExpressionText("`"), "\\`");
    });

    it("expression inside script elements, dollar char", () => {
      assert.equal(scriptExpressionText("$"), "\\$");
    });

    it("expression inside script elements, line feed char", () => {
      assert.equal(scriptExpressionText("\n"), "\\n");
    });

    it("expression inside script elements, carriage return char", () => {
      assert.equal(scriptExpressionText("\r"), "\\r");
    });

    it("expression inside script elements, null char", () => {
      assert.equal(scriptExpressionText("\0"), "\\u{0}");
    });

    it("expression inside script elements, less-than char", () => {
      assert.equal(scriptExpressionText("<"), "\\u{3C}");
    });

    it("expression inside script elements, closing script tag", () => {
      assert.equal(scriptExpressionText("</script>"), "\\u{3C}/script>");
    });

    it("expression inside script elements, template literal expression opener", () => {
      assert.equal(scriptExpressionText("${x}"), "\\${x}");
    });

    it("expression inside script elements, greater-than and ampersand chars travel as themselves", () => {
      assert.equal(scriptExpressionText("a > b & c"), "a > b & c");
    });

    it("expression inside script elements, non-ASCII text travels as itself", () => {
      assert.equal(scriptExpressionText("全息图"), "全息图");
    });

    it("expression inside script elements, text around escaped chars is kept", () => {
      assert.equal(
        scriptExpressionText('say "hi" <b>'),
        'say \\"hi\\" \\u{3C}b>',
      );
    });

    // Note: escaped the same way on the server
    it("expression inside style elements", () => {
      // <style>{"abc < xyz"}</style>
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("style"),
        Type.list(),
        Type.list([
          Type.tuple([
            Type.atom("expression"),
            Type.tuple([Type.bitstring("abc < xyz")]),
          ]),
        ]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode("style", {attrs: {}, on: {}}, [
        "abc \\00003C  xyz",
      ]);

      assert.deepStrictEqual(result, expected);
    });

    // The text an expression contributes to a style element, as rendered by the client.
    const styleExpressionText = (text) => {
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("style"),
        Type.list(),
        Type.list([
          Type.tuple([
            Type.atom("expression"),
            Type.tuple([Type.bitstring(text)]),
          ]),
        ]),
      ]);

      return Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      ).children[0].text;
    };

    it("expression inside style elements, backslash char", () => {
      assert.equal(styleExpressionText("\\"), "\\\\");
    });

    it("expression inside style elements, double quote char", () => {
      assert.equal(styleExpressionText('"'), '\\"');
    });

    it("expression inside style elements, single quote char", () => {
      assert.equal(styleExpressionText("'"), "\\'");
    });

    it("expression inside style elements, line feed char", () => {
      assert.equal(styleExpressionText("\n"), "\\00000A ");
    });

    it("expression inside style elements, carriage return char", () => {
      assert.equal(styleExpressionText("\r"), "\\00000D ");
    });

    it("expression inside style elements, form feed char", () => {
      assert.equal(styleExpressionText("\f"), "\\00000C ");
    });

    it("expression inside style elements, null char", () => {
      assert.equal(styleExpressionText("\0"), "\\00FFFD ");
    });

    it("expression inside style elements, less-than char", () => {
      assert.equal(styleExpressionText("<"), "\\00003C ");
    });

    it("expression inside style elements, closing style tag", () => {
      assert.equal(styleExpressionText("</style>"), "\\00003C /style>");
    });

    it("expression inside style elements, backtick and dollar chars travel as themselves", () => {
      assert.equal(styleExpressionText("`${x}"), "`${x}");
    });

    it("expression inside style elements, greater-than and ampersand chars travel as themselves", () => {
      assert.equal(styleExpressionText("a > b & c"), "a > b & c");
    });

    it("expression inside style elements, space after an escaped char is kept", () => {
      assert.equal(styleExpressionText("a< b"), "a\\00003C  b");
    });

    it("expression inside style elements, hex digit after an escaped char is not absorbed", () => {
      assert.equal(styleExpressionText("<a"), "\\00003C a");
    });

    it("expression inside style elements, non-ASCII text travels as itself", () => {
      assert.equal(styleExpressionText("全息图"), "全息图");
    });

    it("expression inside style elements, text around escaped chars is kept", () => {
      assert.equal(
        styleExpressionText('say "hi" <b>'),
        'say \\"hi\\" \\00003C b>',
      );
    });

    // Note: server-side version escapes
    it("expression inside public comments", () => {
      // <!-- {"abc < xyz"} -->
      const node = Type.tuple([
        Type.atom("public_comment"),
        Type.list([
          Type.tuple([Type.atom("text"), Type.bitstring(" ")]),
          Type.tuple([
            Type.atom("expression"),
            Type.tuple([Type.bitstring("abc < xyz")]),
          ]),
          Type.tuple([Type.atom("text"), Type.bitstring(" ")]),
        ]),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode("!", " abc < xyz ");

      assert.deepStrictEqual(result, expected);
    });

    // Note: server-side version escapes
    it("expression inside non-input attribute", () => {
      // <div class={"abc < xyz"}></div>
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("div"),
        Type.list([
          Type.tuple([
            Type.bitstring("class"),
            Type.list([
              Type.tuple([
                Type.atom("expression"),
                Type.tuple([Type.bitstring("abc < xyz")]),
              ]),
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode("div", {attrs: {class: "abc < xyz"}, on: {}}, []);

      assert.deepStrictEqual(result, expected);
    });

    // Note: server-side version escapes
    it("expression inside input non-controlled attribute", () => {
      // <input type="text" class={"abc < xyz"} />
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("input"),
        Type.list([
          Type.tuple([
            Type.bitstring("type"),
            Type.keywordList([[Type.atom("text"), Type.bitstring("text")]]),
          ]),
          Type.tuple([
            Type.bitstring("class"),
            Type.keywordList([
              [
                Type.atom("expression"),
                Type.tuple([Type.bitstring("abc < xyz")]),
              ],
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode(
        "input",
        {attrs: {class: "abc < xyz", type: "text"}, on: {}},
        [],
      );

      assert.deepStrictEqual(result, expected);
    });

    // Note: server-side version escapes
    it("multi-part attribute", () => {
      // <div class="a < b {"< c <"} d < e"></div>
      const node = Type.tuple([
        Type.atom("element"),
        Type.bitstring("div"),
        Type.list([
          Type.tuple([
            Type.bitstring("class"),
            Type.keywordList([
              [Type.atom("text"), Type.bitstring("a < b ")],
              [Type.atom("expression"), Type.tuple([Type.bitstring("< c <")])],
              [Type.atom("text"), Type.bitstring(" d < e")],
            ]),
          ]),
        ]),
        Type.list(),
      ]);

      const result = Renderer.renderDom(
        node,
        context,
        slots,
        defaultTarget,
        parentTagName,
      );

      const expected = vnode(
        "div",
        {attrs: {class: "a < b < c < d < e"}, on: {}},
        [],
      );

      assert.deepStrictEqual(result, expected);
    });

    describe("client-side only", () => {
      describe("form inputs", () => {
        it("does not escape expressions in text input value attribute", () => {
          // <input type="text" value={"abc < xyz"} />
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.keywordList([
              [
                Type.bitstring("type"),
                Type.keywordList([[Type.atom("text"), Type.bitstring("text")]]),
              ],
              [
                Type.bitstring("value"),
                Type.keywordList([
                  [
                    Type.atom("expression"),
                    Type.tuple([Type.bitstring("abc < xyz")]),
                  ],
                ]),
              ],
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          assert.deepStrictEqual(
            result.data.hologramFormInputValue,
            "abc < xyz",
          );

          assert.deepStrictEqual(
            result.data.attrs["data-hologram-form-input-value"],
            undefined,
          );
        });

        it("does not escape expressions in email input value attribute", () => {
          // <input type="email" value={"abc < xyz"} />
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("input"),
            Type.keywordList([
              [
                Type.bitstring("type"),
                Type.keywordList([
                  [Type.atom("text"), Type.bitstring("email")],
                ]),
              ],
              [
                Type.bitstring("value"),
                Type.keywordList([
                  [
                    Type.atom("expression"),
                    Type.tuple([Type.bitstring("abc < xyz")]),
                  ],
                ]),
              ],
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          assert.deepStrictEqual(
            result.data.hologramFormInputValue,
            "abc < xyz",
          );

          assert.deepStrictEqual(
            result.data.attrs["data-hologram-form-input-value"],
            undefined,
          );
        });

        it("does not escape expressions in textarea value attribute", () => {
          // <textarea value={"abc < xyz"}></textarea>
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("textarea"),
            Type.keywordList([
              [
                Type.bitstring("value"),
                Type.keywordList([
                  [
                    Type.atom("expression"),
                    Type.tuple([Type.bitstring("abc < xyz")]),
                  ],
                ]),
              ],
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          assert.deepStrictEqual(
            result.data.hologramFormInputValue,
            "abc < xyz",
          );

          assert.deepStrictEqual(
            result.data.attrs["data-hologram-form-input-value"],
            undefined,
          );
        });

        it("does not escape expressions in select value attribute", () => {
          // <select value={"abc < xyz"}></select>
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("select"),
            Type.keywordList([
              [
                Type.bitstring("value"),
                Type.keywordList([
                  [
                    Type.atom("expression"),
                    Type.tuple([Type.bitstring("abc < xyz")]),
                  ],
                ]),
              ],
            ]),
            Type.list(),
          ]);

          const result = Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
          );

          assert.deepStrictEqual(
            result.data.hologramFormInputValue,
            "abc < xyz",
          );

          assert.deepStrictEqual(
            result.data.attrs["data-hologram-form-input-value"],
            undefined,
          );
        });
      });
    });
  });

  describe("decodeTree()", () => {
    const text = (str) => Type.tuple([Type.atom("text"), Type.bitstring(str)]);

    const attribute = (name, value) =>
      Type.tuple([
        Type.bitstring(name),
        Type.keywordList([[Type.atom("text"), Type.bitstring(value)]]),
      ]);

    const booleanAttribute = (name) =>
      Type.tuple([Type.bitstring(name), Type.list([])]);

    const element = (tagName, attributes = [], children = []) =>
      Type.tuple([
        Type.atom("element"),
        Type.bitstring(tagName),
        Type.list(attributes),
        Type.list(children),
      ]);

    // Mirrors the cases in the Elixir encode_tree/1 tests, one for one.

    it("text node", () => {
      assert.deepStrictEqual(
        Renderer.decodeTree(["abc < xyz"]),
        Type.list([text("abc < xyz")]),
      );
    });

    it("doctype node", () => {
      assert.deepStrictEqual(
        Renderer.decodeTree([["d", "html"]]),
        Type.list([Type.tuple([Type.atom("doctype"), Type.bitstring("html")])]),
      );
    });

    it("element node, without attributes or children", () => {
      assert.deepStrictEqual(
        Renderer.decodeTree([["div", [], []]]),
        Type.list([element("div")]),
      );
    });

    it("element node, with attribute", () => {
      assert.deepStrictEqual(
        Renderer.decodeTree([["div", ["class", "big"], []]]),
        Type.list([element("div", [attribute("class", "big")])]),
      );
    });

    it("element node, with boolean attribute", () => {
      assert.deepStrictEqual(
        Renderer.decodeTree([["input", ["disabled", null], []]]),
        Type.list([element("input", [booleanAttribute("disabled")])]),
      );
    });

    it("element node, with multiple attributes", () => {
      const result = Renderer.decodeTree([
        ["div", ["class", "big", "hidden", null, "id", "abc"], []],
      ]);

      const expected = Type.list([
        element("div", [
          attribute("class", "big"),
          booleanAttribute("hidden"),
          attribute("id", "abc"),
        ]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("element node, with element key", () => {
      assert.deepStrictEqual(
        Renderer.decodeTree([["div", ["$key", "k1:0"], []]]),
        Type.list([element("div", [attribute("$key", "k1:0")])]),
      );
    });

    it("element node, with children", () => {
      const result = Renderer.decodeTree([
        ["div", [], ["abc", ["span", [], []]]],
      ]);

      const expected = Type.list([
        element("div", [], [text("abc"), element("span")]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("element node, nested", () => {
      const result = Renderer.decodeTree([
        ["div", [], [["span", [], [["b", [], ["abc"]]]]]],
      ]);

      const expected = Type.list([
        element(
          "div",
          [],
          [element("span", [], [element("b", [], [text("abc")])])],
        ),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("public comment node", () => {
      assert.deepStrictEqual(
        Renderer.decodeTree([["c", ["abc"]]]),
        Type.list([
          Type.tuple([Type.atom("public_comment"), Type.list([text("abc")])]),
        ]),
      );
    });

    it("public comment node, with multiple children", () => {
      const result = Renderer.decodeTree([["c", ["abc", ["div", [], []]]]]);

      const expected = Type.list([
        Type.tuple([
          Type.atom("public_comment"),
          Type.list([text("abc"), element("div")]),
        ]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("node list", () => {
      const result = Renderer.decodeTree([
        "abc",
        ["div", [], []],
        ["d", "html"],
      ]);

      const expected = Type.list([
        text("abc"),
        element("div"),
        Type.tuple([Type.atom("doctype"), Type.bitstring("html")]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("empty node list", () => {
      assert.deepStrictEqual(Renderer.decodeTree([]), Type.list([]));
    });

    // The guard that lets renderTree's WARNING keep holding: a decoded wire form and the boxed
    // tree it came from must render to the same vnodes, or a navigation rebuilds what it should
    // have adopted.
    it("renders to the vnodes the equivalent boxed tree renders to", () => {
      const wire = [
        ["d", "html"],
        [
          "html",
          [],
          [
            ["head", [], []],
            [
              "body",
              ["class", "page"],
              [
                ["div", ["$key", "k1:0", "hidden", null], ["abc"]],
                ["c", ["a comment"]],
              ],
            ],
          ],
        ],
      ];

      const boxed = Type.list([
        Type.tuple([Type.atom("doctype"), Type.bitstring("html")]),
        element(
          "html",
          [],
          [
            element("head"),
            element(
              "body",
              [attribute("class", "page")],
              [
                element(
                  "div",
                  [attribute("$key", "k1:0"), booleanAttribute("hidden")],
                  [text("abc")],
                ),
                Type.tuple([
                  Type.atom("public_comment"),
                  Type.list([text("a comment")]),
                ]),
              ],
            ),
          ],
        ),
      ]);

      assert.deepStrictEqual(Renderer.decodeTree(wire), boxed);

      assert.deepStrictEqual(
        Renderer.renderTree(Renderer.decodeTree(wire)),
        Renderer.renderTree(boxed),
      );
    });
  });

  describe("renderTree()", () => {
    const text = (str) => Type.tuple([Type.atom("text"), Type.bitstring(str)]);

    const attribute = (name, value) =>
      Type.tuple([
        Type.bitstring(name),
        Type.keywordList([[Type.atom("text"), Type.bitstring(value)]]),
      ]);

    const treeElement = (tagName, attributes = [], childrenTree = []) =>
      Type.tuple([
        Type.atom("element"),
        Type.bitstring(tagName),
        Type.list(attributes),
        Type.list(childrenTree),
      ]);

    // A page tree is the document's children, so a single node is wrapped in the list one
    // always is.
    const tree = (...nodes) => Type.list(nodes);

    it("wraps a tree naming no html element in the elements a document must have", () => {
      const result = Renderer.renderTree(tree(treeElement("div")));

      const expected = vnode("html", {attrs: {}, on: {}}, [
        vnode("body", {attrs: {}, on: {}}, [
          vnode("div", {attrs: {}, on: {}}, []),
        ]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("takes the html element a tree names as the document root", () => {
      const treeDom = tree(
        treeElement("html", [], [treeElement("body", [], [text("abc")])]),
      );

      const result = Renderer.renderTree(treeDom);

      const expected = vnode("html", {attrs: {}, on: {}}, [
        vnode("body", {attrs: {}, on: {}}, ["abc"]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("renders the doctype a tree carries to nothing", () => {
      const treeDom = tree(
        Type.tuple([Type.atom("doctype"), Type.bitstring("html")]),
        treeElement("html", [], []),
      );

      const result = Renderer.renderTree(treeDom);

      assert.deepStrictEqual(result, vnode("html", {attrs: {}, on: {}}, []));
    });

    it("renders an element's attributes and children", () => {
      const treeDom = tree(
        treeElement("div", [attribute("class", "big")], [text("abc")]),
      );

      const result = Renderer.renderTree(treeDom);

      assert.deepStrictEqual(result.children[0].children, [
        vnode("div", {attrs: {class: "big"}, on: {}}, ["abc"]),
      ]);
    });

    it("renders an attribute with an empty value list as a boolean attribute", () => {
      const hiddenAttribute = Type.tuple([
        Type.bitstring("hidden"),
        Type.list(),
      ]);

      const treeDom = tree(treeElement("div", [hiddenAttribute]));

      const result = Renderer.renderTree(treeDom);

      assert.deepStrictEqual(result.children[0].children[0].data.attrs, {
        hidden: true,
      });
    });

    it("merges adjacent text nodes", () => {
      const treeDom = tree(
        treeElement("div", [], [text("aaa"), text("bbb"), text("ccc")]),
      );

      const result = Renderer.renderTree(treeDom);

      assert.deepStrictEqual(result.children[0].children, [
        vnode("div", {attrs: {}, on: {}}, ["aaabbbccc"]),
      ]);
    });

    it("takes an element's $key attribute as its vnode key", () => {
      const treeDom = tree(
        treeElement("div", [attribute("$key", "1a2b3c:4")], []),
      );

      const result = Renderer.renderTree(treeDom);

      const divVnode = result.children[0].children[0];

      assert.equal(divVnode.key, "1a2b3c:4");
      assert.isUndefined(divVnode.data.attrs["$key"]);
    });

    it("numbers repeated keys by occurrence", () => {
      const item = treeElement("li", [attribute("$key", "1a2b3c:4")], []);
      const treeDom = tree(treeElement("ul", [], [item, item, item]));

      const result = Renderer.renderTree(treeDom);

      const keys = result.children[0].children[0].children.map(
        (childVnode) => childVnode.key,
      );

      assert.deepStrictEqual(keys, ["1a2b3c:4", "1a2b3c:4:1", "1a2b3c:4:2"]);
    });

    it("keys a script element by the source it loads", () => {
      const treeDom = tree(
        treeElement("script", [attribute("src", "/hologram/page-abc.js")]),
      );

      const result = Renderer.renderTree(treeDom);

      assert.equal(
        result.children[0].children[0].key,
        "__hologramScript__:/hologram/page-abc.js",
      );
    });

    it("keys an inline script element by the code it holds", () => {
      const treeDom = tree(treeElement("script", [], [text("var abc = 1;")]));

      const result = Renderer.renderTree(treeDom);

      assert.equal(
        result.children[0].children[0].key,
        "__hologramScript__:var abc = 1;",
      );
    });

    it("keys a link element by what it loads", () => {
      const treeDom = tree(
        treeElement("link", [attribute("href", "/my-stylesheet.css")]),
      );

      const result = Renderer.renderTree(treeDom);

      assert.equal(
        result.children[0].children[0].key,
        "__hologramLink__:/my-stylesheet.css",
      );
    });

    it("sets up the value hooks a controlled input needs", () => {
      const treeDom = tree(
        treeElement("input", [attribute("value", "my_value")]),
      );

      const result = Renderer.renderTree(treeDom);

      const inputVnode = result.children[0].children[0];

      assert.isUndefined(inputVnode.data.attrs.value);

      assert.isUndefined(
        inputVnode.data.attrs["data-hologram-form-input-value"],
      );

      assert.strictEqual(typeof inputVnode.data.hook.create, "function");
      assert.strictEqual(typeof inputVnode.data.hook.update, "function");
    });
  });

  describe("toBitstring()", () => {
    const toBitstring = Renderer.toBitstring;

    it("is a bitstring", () => {
      const term = Bitstring.fromBytes([97, 98, 99]);
      assert.equal(toBitstring(term), term);
    });

    it("is not a bitstring", () => {
      const term = Type.integer(123);
      assert.deepStrictEqual(toBitstring(term), Type.bitstring("123"));
    });
  });

  describe("toText()", () => {
    const dummyStringCharsProtocolResult = "Dummy String.Chars protocol result";
    const toText = Renderer.toText;

    it("anonymous function", () => {
      const clauses = ["dummy_clause_1", "dummy_clause_2"];
      const context = contextFixture();
      const term = Type.anonymousFunction(2, clauses, context);
      const result = toText(term);

      assert.equal(result, dummyStringCharsProtocolResult);
    });

    describe("atom", () => {
      it("non-boolean and non-nil", () => {
        const term = Type.atom("abc");
        const result = toText(term);

        assert.equal(result, "abc");
      });

      it("true", () => {
        const term = Type.boolean(true);
        const result = toText(term);

        assert.equal(result, "true");
      });

      it("false", () => {
        const term = Type.boolean(false);
        const result = toText(term);

        assert.equal(result, "false");
      });

      it("nil", () => {
        const term = Type.nil();
        const result = toText(term);

        assert.equal(result, "");
      });
    });

    describe("bitstring", () => {
      it("binary", () => {
        const term = Bitstring.fromBytes([97, 98, 99]);
        const result = toText(term);

        assert.equal(result, "abc");
      });

      it("non-binary", () => {
        const segment1 = Type.bitstringSegment(Type.integer(97), {
          type: "integer",
          size: Type.integer(6),
          unit: 1n,
        });

        const segment2 = Type.bitstringSegment(Type.integer(98), {
          type: "integer",
          size: Type.integer(4),
          unit: 1n,
        });

        const term = Bitstring.fromSegments([segment1, segment2]);
        const result = toText(term);

        assert.equal(result, dummyStringCharsProtocolResult);
      });
    });

    it("float", () => {
      const term = Type.float(1.23);
      const result = toText(term);

      assert.equal(result, "1.23");
    });

    it("integer", () => {
      const term = Type.integer(123);
      const result = toText(term);

      assert.equal(result, "123");
    });

    it("list", () => {
      const term = Type.list([Type.integer(1), Type.integer(2)]);
      const result = toText(term);

      assert.equal(result, dummyStringCharsProtocolResult);
    });

    it("map", () => {
      const term = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ]);

      const result = toText(term);

      assert.equal(result, dummyStringCharsProtocolResult);
    });

    it("PID", () => {
      const term = Type.pid("my_node", [0, 11, 222], "server");
      const result = toText(term);

      assert.equal(result, dummyStringCharsProtocolResult);
    });

    it("port", () => {
      const term = Type.port("my_node", [0, 11], "server");
      const result = toText(term);

      assert.equal(result, dummyStringCharsProtocolResult);
    });

    it("reference", () => {
      const term = Type.reference("my_node", [0, 1, 2, 3], "server");
      const result = toText(term);

      assert.equal(result, dummyStringCharsProtocolResult);
    });

    it("tuple", () => {
      const term = Type.tuple([Type.integer(1), Type.integer(2)]);
      const result = toText(term);

      assert.equal(result, dummyStringCharsProtocolResult);
    });
  });

  describe("valueDomToBitstring()", () => {
    it("text", () => {
      const dom = Type.keywordList([
        [Type.atom("text"), Type.bitstring("aaa")],
      ]);

      const result = Renderer.valueDomToBitstring(dom);

      assert.deepStrictEqual(result, Type.bitstring("aaa"));
    });

    it("expression", () => {
      const dom = Type.keywordList([
        [Type.atom("expression"), Type.tuple([Type.integer(123)])],
      ]);

      const result = Renderer.valueDomToBitstring(dom);

      assert.deepStrictEqual(result, Type.bitstring("123"));
    });

    it("text, expression", () => {
      const dom = Type.keywordList([
        [Type.atom("text"), Type.bitstring("aaa")],
        [Type.atom("expression"), Type.tuple([Type.integer(123)])],
      ]);

      const result = Renderer.valueDomToBitstring(dom);

      assert.deepStrictEqual(result, Type.bitstring("aaa123"));
    });

    it("expression, text", () => {
      const dom = Type.keywordList([
        [Type.atom("expression"), Type.tuple([Type.integer(123)])],
        [Type.atom("text"), Type.bitstring("aaa")],
      ]);

      const result = Renderer.valueDomToBitstring(dom);

      assert.deepStrictEqual(result, Type.bitstring("123aaa"));
    });

    it("text, expression, text", () => {
      const dom = Type.keywordList([
        [Type.atom("text"), Type.bitstring("aaa")],
        [Type.atom("expression"), Type.tuple([Type.integer(123)])],
        [Type.atom("text"), Type.bitstring("bbb")],
      ]);

      const result = Renderer.valueDomToBitstring(dom);

      assert.deepStrictEqual(result, Type.bitstring("aaa123bbb"));
    });

    it("expression, text, expression", () => {
      const dom = Type.keywordList([
        [Type.atom("expression"), Type.tuple([Type.integer(123)])],
        [Type.atom("text"), Type.bitstring("aaa")],
        [Type.atom("expression"), Type.tuple([Type.integer(987)])],
      ]);

      const result = Renderer.valueDomToBitstring(dom);

      assert.deepStrictEqual(result, Type.bitstring("123aaa987"));
    });

    describe("is not escaped (client-side escaping is delegated to Snabbdom)", () => {
      it("text", () => {
        const dom = Type.keywordList([
          [Type.atom("text"), Type.bitstring("abc < xyz")],
        ]);

        const result = Renderer.valueDomToBitstring(dom);

        assert.deepStrictEqual(result, Type.bitstring("abc < xyz"));
      });

      it("expression", () => {
        const dom = Type.keywordList([
          [Type.atom("expression"), Type.tuple([Type.bitstring("abc < xyz")])],
        ]);

        const result = Renderer.valueDomToBitstring(dom);

        assert.deepStrictEqual(result, Type.bitstring("abc < xyz"));
      });

      it("mixed text and expression", () => {
        const dom = Type.keywordList([
          [Type.atom("text"), Type.bitstring("a < b")],
          [Type.atom("expression"), Type.tuple([Type.bitstring(" < c < ")])],
          [Type.atom("text"), Type.bitstring("d < e")],
        ]);

        const result = Renderer.valueDomToBitstring(dom);

        assert.deepStrictEqual(result, Type.bitstring("a < b < c < d < e"));
      });
    });
  });

  describe("queuing actions from client-side init/2", () => {
    beforeEach(() => {
      InitActionQueue.queue = [];
    });

    it("does not queue action when init/2 doesn't set next action", () => {
      const cid = Type.bitstring("my_component");

      const node = Type.tuple([
        Type.atom("component"),
        Type.alias("Hologram.Test.Fixtures.Template.Renderer.Module3"),
        Type.list([
          Type.tuple([
            Type.bitstring("cid"),
            Type.keywordList([[Type.atom("text"), cid]]),
          ]),
        ]),
        Type.list(),
      ]);

      // Render the component - should trigger init/2 without next_action
      Renderer.renderDom(node, context, slots, defaultTarget, parentTagName);

      // Check that no action was queued
      assert.strictEqual(InitActionQueue.queue.length, 0);
    });

    it("does not queue action when component is already initialized", () => {
      const cid = Type.bitstring("my_component");

      // Pre-initialize the component in registry
      const entry = componentRegistryEntryFixture({
        module: Type.alias(
          "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module1",
        ),
        state: Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
        ]),
      });
      ComponentRegistry.putEntry(cid, entry);

      const node = Type.tuple([
        Type.atom("component"),
        Type.alias(
          "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module1",
        ),
        Type.list([
          Type.tuple([
            Type.bitstring("cid"),
            Type.keywordList([[Type.atom("text"), cid]]),
          ]),
        ]),
        Type.list(),
      ]);

      // Render the component - should not trigger init/2 since already initialized
      Renderer.renderDom(node, context, slots, defaultTarget, parentTagName);

      // Check that no action was queued
      assert.strictEqual(InitActionQueue.queue.length, 0);
    });

    it("queues action when init/2 sets next action", () => {
      const cid = Type.bitstring("my_component");

      const node = Type.tuple([
        Type.atom("component"),
        Type.alias(
          "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module1",
        ),
        Type.list([
          Type.tuple([
            Type.bitstring("cid"),
            Type.keywordList([[Type.atom("text"), cid]]),
          ]),
        ]),
        Type.list(),
      ]);

      // Render the component - should trigger init/2 and queue the action
      Renderer.renderDom(node, context, slots, defaultTarget, parentTagName);

      // Check that action was queued with original target preserved

      assert.strictEqual(InitActionQueue.queue.length, 1);

      const queuedAction = InitActionQueue.queue[0];

      assert.deepStrictEqual(
        Erlang_Maps["get/2"](Type.atom("name"), queuedAction),
        Type.atom("test_action_from_init"),
      );

      assert.deepStrictEqual(
        Erlang_Maps["get/2"](Type.atom("target"), queuedAction),
        Type.bitstring("custom_target_from_init"),
      );
    });

    it("sets the current component as the target when init/2 sets next action that doesn't have target specified", () => {
      const cid = Type.bitstring("my_component");

      const node = Type.tuple([
        Type.atom("component"),
        Type.alias(
          "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module2",
        ),
        Type.list([
          Type.tuple([
            Type.bitstring("cid"),
            Type.keywordList([[Type.atom("text"), cid]]),
          ]),
        ]),
        Type.list(),
      ]);

      // Render the component - should trigger init/2 and queue the action
      Renderer.renderDom(node, context, slots, defaultTarget, parentTagName);

      // Check that action was queued with target added

      assert.strictEqual(InitActionQueue.queue.length, 1);

      const queuedAction = InitActionQueue.queue[0];

      assert.deepStrictEqual(
        Erlang_Maps["get/2"](Type.atom("name"), queuedAction),
        Type.atom("targetless_action_from_init"),
      );

      assert.deepStrictEqual(
        Erlang_Maps["get/2"](Type.atom("target"), queuedAction),
        cid,
      );
    });

    it("clears next_action from the component struct in the registry after queueing", () => {
      const cid = Type.bitstring("my_component");

      const node = Type.tuple([
        Type.atom("component"),
        Type.alias(
          "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module1",
        ),
        Type.list([
          Type.tuple([
            Type.bitstring("cid"),
            Type.keywordList([[Type.atom("text"), cid]]),
          ]),
        ]),
        Type.list(),
      ]);

      Renderer.renderDom(node, context, slots, defaultTarget, parentTagName);

      const struct = ComponentRegistry.getComponentStruct(cid);

      assert.deepStrictEqual(
        Erlang_Maps["get/2"](Type.atom("next_action"), struct),
        Type.nil(),
      );
    });
  });
});
