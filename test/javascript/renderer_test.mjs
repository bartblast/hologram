// Based on Elixir Hologram.Template.RendererTest

"use strict";

import {
  assert,
  assertBoxedError,
  componentRegistryEntryFixture,
  contextFixture,
  defineGlobalErlangAndElixirModules,
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
import {defineModule8Fixture} from "./support/fixtures/renderer/module_8.mjs";
import {defineModule9Fixture} from "./support/fixtures/renderer/module_9.mjs";
import {defineClientOnlyModule1Fixture} from "./support/fixtures/renderer/client_only/module_1.mjs";
import {defineClientOnlyModule2Fixture} from "./support/fixtures/renderer/client_only/module_2.mjs";

import Bitstring from "../../assets/js/bitstring.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import InitActionQueue from "../../assets/js/init_action_queue.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import Renderer from "../../assets/js/renderer.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

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
defineModule8Fixture();
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
        state: Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
        ]),
      });

      ComponentRegistry.putEntry(cid3, entry3);

      const entry7 = componentRegistryEntryFixture({
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
        state: Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
        ]),
      });

      ComponentRegistry.putEntry(cid3, entry3);

      const entry7 = componentRegistryEntryFixture({
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

        it("event type mapping", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("div"),
            Type.list([
              Type.tuple([
                Type.bitstring("$mouse_move"),
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
                Type.keywordList([[Type.atom("text"), Type.bitstring("text")]]),
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

        it("maps $change event to $input event for textarea element", () => {
          const node = Type.tuple([
            Type.atom("element"),
            Type.bitstring("textarea"),
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

          initComponentRegistryEntry(cid);

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
          initComponentRegistryEntry(Type.bitstring("page"));
          initComponentRegistryEntry(Type.bitstring("layout"));

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
          initComponentRegistryEntry(Type.bitstring("page"));
          initComponentRegistryEntry(Type.bitstring("layout"));

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

          initComponentRegistryEntry(Type.bitstring("component_59"));
          initComponentRegistryEntry(Type.bitstring("component_60"));
          initComponentRegistryEntry(Type.bitstring("component_61"));

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
        state: Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
        ]),
      });

      ComponentRegistry.putEntry(cid3, entry3);

      const entry7 = componentRegistryEntryFixture({
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
        state: Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
        ]),
      });

      ComponentRegistry.putEntry(cid51, entry51);

      const entry52 = componentRegistryEntryFixture({
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

      initComponentRegistryEntry(Type.bitstring("component_37"));

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

      initComponentRegistryEntry(Type.bitstring("component_76"));

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
        Interpreter.buildKeyErrorMsg(Type.atom("aaa"), Type.map()),
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

      initComponentRegistryEntry(Type.bitstring("component_77"));

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
        Interpreter.buildKeyErrorMsg(
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

      initComponentRegistryEntry(cid);

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
        [cid, componentRegistryEntryFixture()],
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

      initComponentRegistryEntry(cid);

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
        [cid, componentRegistryEntryFixture()],
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

      initComponentRegistryEntry(cid);

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
        state: Type.map([[Type.atom("b"), Type.integer(222)]]),
      });

      ComponentRegistry.putEntry(cid, entry);

      const expectedMessage = Interpreter.buildKeyErrorMsg(
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
        state: Type.map([[Type.atom("a"), Type.integer(10)]]),
      });

      ComponentRegistry.putEntry(cid10, entry10);

      const entry11 = componentRegistryEntryFixture({
        state: Type.map([[Type.atom("a"), Type.integer(11)]]),
      });

      ComponentRegistry.putEntry(cid11, entry11);

      const entry12 = componentRegistryEntryFixture({
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
        state: Type.map([
          [Type.atom("cid"), cid35],
          [Type.atom("a"), Type.bitstring("35a_prop")],
          [Type.atom("z"), Type.bitstring("35z_state")],
        ]),
      });

      ComponentRegistry.putEntry(cid35, entry35);

      const entry36 = componentRegistryEntryFixture({
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

  describe("context", () => {
    it("emitted in page, accessed in component nested in page", () => {
      initComponentRegistryEntry(Type.bitstring("layout"));

      const pageEntry = componentRegistryEntryFixture({
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
      initComponentRegistryEntry(Type.bitstring("layout"));

      const pageEntry = componentRegistryEntryFixture({
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
      initComponentRegistryEntry(Type.bitstring("layout"));

      const pageEntry = componentRegistryEntryFixture({
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
      initComponentRegistryEntry(Type.bitstring("page"));

      const layoutEntry = componentRegistryEntryFixture({
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
      initComponentRegistryEntry(Type.bitstring("page"));

      const layoutEntry = componentRegistryEntryFixture({
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
      initComponentRegistryEntry(Type.bitstring("page"));
      initComponentRegistryEntry(Type.bitstring("layout"));

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
      initComponentRegistryEntry(Type.bitstring("page"));
      initComponentRegistryEntry(Type.bitstring("layout"));

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
        state: Type.map([
          [Type.atom("prop_1"), Type.bitstring("prop_value_1")],
          [Type.atom("prop_2"), Type.bitstring("prop_value_2")],
          [Type.atom("prop_3"), Type.bitstring("prop_value_3")],
        ]),
      });

      ComponentRegistry.putEntry(Type.bitstring("page"), pageEntry);

      initComponentRegistryEntry(Type.bitstring("layout"));

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
        state: Type.map([
          [Type.atom("key_2"), Type.bitstring("state_value_2")],
          [Type.atom("key_3"), Type.bitstring("state_value_3")],
        ]),
      });

      ComponentRegistry.putEntry(Type.bitstring("page"), pageEntry);

      initComponentRegistryEntry(Type.bitstring("layout"));

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
      initComponentRegistryEntry(Type.bitstring("page"));

      const layoutEntry = componentRegistryEntryFixture({
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
      initComponentRegistryEntry(Type.bitstring("page"));
      initComponentRegistryEntry(Type.bitstring("layout"));

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
      initComponentRegistryEntry(Type.bitstring("page"));
      initComponentRegistryEntry(Type.bitstring("layout"));

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
    it("text inside non-script elements", () => {
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
    it("expression inside non-script elements", () => {
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

    // Note: server-side version escapes
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
        {attrs: {}, key: "__hologramScript__:abc < xyz", on: {}},
        ["abc < xyz"],
      );

      assert.deepStrictEqual(result, expected);
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
    const dummyStringCharsProtocolResult =
      "Test String.Chars protocol implementation";

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
  });
});
