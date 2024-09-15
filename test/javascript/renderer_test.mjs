// Based on Elixir Hologram.Template.RendererTest

"use strict";

import {
  assert,
  assertBoxedError,
  componentRegistryEntryFixture,
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
import {defineModule7Fixture} from "./support/fixtures/renderer/module_7.mjs";
import {defineModule8Fixture} from "./support/fixtures/renderer/module_8.mjs";
import {defineModule9Fixture} from "./support/fixtures/renderer/module_9.mjs";

import ComponentRegistry from "../../assets/js/component_registry.mjs";
import Hologram from "../../assets/js/hologram.mjs";
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
defineModule7Fixture();
defineModule8Fixture();
defineModule9Fixture();

describe("Renderer", () => {
  beforeEach(() => {
    ComponentRegistry.clear();
  });

  const cid = Type.bitstring("my_component");
  const context = Type.map();
  const defaultTarget = Type.bitstring("my_default_target");
  const slots = Type.keywordList();

  it("text node", () => {
    const node = Type.tuple([Type.atom("text"), Type.bitstring("abc")]);
    const result = Renderer.renderDom(node, context, slots, defaultTarget);

    assert.equal(result, "abc");
  });

  describe("public comment node", () => {
    it("empty", () => {
      // <!---->
      const node = Type.tuple([Type.atom("public_comment"), Type.list()]);

      const result = Renderer.renderDom(node, context, slots, defaultTarget);
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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);
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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);
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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);

      const expected = vnode(
        "!",
        '<div attr="value"><div>state_a = 1, state_b = 2</div><div>state_c = 3, state_d = 4</div></div>',
      );

      assert.deepStrictEqual(result, expected);
    });
  });

  it("DOCTYPE node", () => {
    const node = Type.tuple([Type.atom("doctype"), Type.bitstring("html")]);
    const result = Renderer.renderDom(node, context, slots, defaultTarget);

    assert.deepStrictEqual(result, Type.nil());
  });

  it("expression node", () => {
    const node = Type.tuple([
      Type.atom("expression"),
      Type.tuple([Type.integer(123)]),
    ]);

    const result = Renderer.renderDom(node, context, slots, defaultTarget);

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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);
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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);

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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);

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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);
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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);

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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);

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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);

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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);

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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);

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

          const vdom = Renderer.renderDom(node, context, slots, defaultTarget);

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

          const vdom = Renderer.renderDom(node, context, slots, defaultTarget);

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

          const vdom = Renderer.renderDom(node, context, slots, defaultTarget);

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

          const vdom = Renderer.renderDom(node, context, slots, defaultTarget);

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

          sinon.assert.calledWith(
            stub,
            "dummyEvent",
            "click",
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
            ]),
            Type.bitstring("layout"),
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

          const vdom = Renderer.renderDom(node, context, slots, defaultTarget);

          const stub = sinon
            .stub(Hologram, "handleUiEvent")
            .callsFake(
              (_event, _eventType, _operationSpecVdom, _defaultTarget) => null,
            );

          vdom[0].children[1].children[1].data.on.click("dummyEvent");

          sinon.assert.calledWith(
            stub,
            "dummyEvent",
            "click",
            Type.list([
              Type.tuple([Type.atom("text"), Type.bitstring("my_action")]),
            ]),
            Type.bitstring("component_61"),
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
          );

          const expected = vnode("script", {attrs: {}, on: {}}, []);

          assert.deepStrictEqual(result, expected);
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

      const result = Renderer.renderDom(nodes, context, slots, defaultTarget);
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

      const result = Renderer.renderDom(nodes, context, slots, defaultTarget);

      assert.deepStrictEqual(result, ["aaa111bbb222"]);
    });

    it("nil nodes", () => {
      const nodes = Type.list([
        Type.tuple([Type.atom("text"), Type.bitstring("aaa")]),
        Type.nil(),
        Type.tuple([Type.atom("text"), Type.bitstring("bbb")]),
        Type.nil(),
      ]);

      const result = Renderer.renderDom(nodes, context, slots, defaultTarget);

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

      const result = Renderer.renderDom(nodes, context, slots, defaultTarget);

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

      const result = Renderer.renderDom(nodes, context, slots, defaultTarget);

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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);
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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);
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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);
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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);
      const expected = ["component vars = %{prop_2: :xyz}"];

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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);
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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);

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
        () => Renderer.renderDom(node, context, slots, defaultTarget),
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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);

      assert.equal(
        result,
        'component vars = %{cid: "my_component", prop_1: "value_1", prop_2: 2, prop_3: "aaa2bbb"}',
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
        () => Renderer.renderDom(node, context, slots, defaultTarget),
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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);

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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);

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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);

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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);
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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);

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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);

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

      const result = Renderer.renderDom(node, context, slots, defaultTarget);

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

    // This test case doesn't apply to the client renderer, because the client renderer receives already casted page params.
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
  });
});
