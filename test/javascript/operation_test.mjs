"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Operation from "../../assets/js/operation.mjs";
import Type from "../../assets/js/type.mjs";

const defaultTarget = Type.bitstring("my_default_target");
const eventParam = "my_event_param";

defineGlobalErlangAndElixirModules();

describe("Operation", () => {
  describe("fromSpecDom()", () => {
    it("single text chunk", () => {
      // Example: $click="my_action"
      // Spec DOM: [text: "my_action"], which is equivalent to [{:text, "my_action"}]
      const specDom = Type.keywordList([
        [Type.atom("text"), Type.bitstring("my_action")],
      ]);

      const operation = Operation.fromSpecDom(
        specDom,
        defaultTarget,
        eventParam,
      );

      assert.deepStrictEqual(
        operation,
        Type.actionStruct({
          name: Type.atom("my_action"),
          params: Type.map([[Type.atom("event"), eventParam]]),
          target: defaultTarget,
        }),
      );
    });

    it("single expression chunk, shorthand syntax, no params", () => {
      // Example: $click={:my_action}
      // Spec DOM: [expression: {:my_action}],
      // which is equivalent to [{:expression, {:my_action}}]
      const specDom = Type.keywordList([
        [Type.atom("expression"), Type.tuple([Type.atom("my_action")])],
      ]);

      const operation = Operation.fromSpecDom(
        specDom,
        defaultTarget,
        eventParam,
      );

      assert.deepStrictEqual(
        operation,
        Type.actionStruct({
          name: Type.atom("my_action"),
          params: Type.map([[Type.atom("event"), eventParam]]),
          target: defaultTarget,
        }),
      );
    });

    it("single expression chunk, shorthand syntax, with params", () => {
      // Example: $click={:my_action, a: 1, b: 2}
      // Spec DOM: [expression: {:my_action, a: 1, b: 2}],
      // which is equivalent to [{:expression, {:my_action, [{:a, 1}, {:b, 2}]}}]
      const specDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.atom("my_action"),
            Type.keywordList([
              [Type.atom("a"), Type.integer(1)],
              [Type.atom("b"), Type.integer(2)],
            ]),
          ]),
        ],
      ]);

      const operation = Operation.fromSpecDom(
        specDom,
        defaultTarget,
        eventParam,
      );

      assert.deepStrictEqual(
        operation,
        Type.actionStruct({
          name: Type.atom("my_action"),
          params: Type.map([
            [Type.atom("a"), Type.integer(1)],
            [Type.atom("b"), Type.integer(2)],
            [Type.atom("event"), eventParam],
          ]),
          target: defaultTarget,
        }),
      );
    });

    it("single expression chunk, longhand syntax, action, no params, default target", () => {
      // Example: $click={action: :my_action}
      // Spec DOM: [expression: {[action: :my_action]}],
      // which is equivalent to [{:expression, {[{:action, :my_action}]}}]
      const specDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([[Type.atom("action"), Type.atom("my_action")]]),
          ]),
        ],
      ]);

      const operation = Operation.fromSpecDom(
        specDom,
        defaultTarget,
        eventParam,
      );

      assert.deepStrictEqual(
        operation,
        Type.actionStruct({
          name: Type.atom("my_action"),
          params: Type.map([[Type.atom("event"), eventParam]]),
          target: defaultTarget,
        }),
      );
    });

    it("single expression chunk, longhand syntax, command, no params, default target", () => {
      // Example: $click={command: :my_command}
      // Spec DOM: [expression: {[command: :my_command]}],
      // which is equivalent to [{:expression, {[{:command, :my_command}]}}]
      const specDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([[Type.atom("command"), Type.atom("my_command")]]),
          ]),
        ],
      ]);

      const operation = Operation.fromSpecDom(
        specDom,
        defaultTarget,
        eventParam,
      );

      assert.deepStrictEqual(
        operation,
        Type.commandStruct({
          name: Type.atom("my_command"),
          params: Type.map([[Type.atom("event"), eventParam]]),
          target: defaultTarget,
        }),
      );
    });

    it("single expression chunk, longhand syntax, target specified", () => {
      // Example: $click={action: :my_action, target: "my_target"}
      // Spec DOM: [expression: {[action: :my_action, target: "my_target"]}],
      // which is equivalent to [{:expression, {[{:action, :my_action}, {:target, "my_target"}]}}]
      const specDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([
              [Type.atom("action"), Type.atom("my_action")],
              [Type.atom("target"), Type.bitstring("my_target")],
            ]),
          ]),
        ],
      ]);

      const operation = Operation.fromSpecDom(
        specDom,
        defaultTarget,
        eventParam,
      );

      assert.deepStrictEqual(
        operation,
        Type.actionStruct({
          name: Type.atom("my_action"),
          params: Type.map([[Type.atom("event"), eventParam]]),
          target: Type.bitstring("my_target"),
        }),
      );
    });

    it("single expression chunk, longhand syntax, with params", () => {
      // Example: $click={action: :my_action, params: %{a: 1, b: 2}}
      // Spec DOM: [expression: {[action: :my_action, params: %{a: 1, b: 2}]}],
      // which is equivalent to [{:expression, {[{:action, :my_action}, {:params, %{a: 1, b: 2}}]}}]
      const specDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([
              [Type.atom("action"), Type.atom("my_action")],
              [
                Type.atom("params"),
                Type.map([
                  [Type.atom("a"), Type.integer(1)],
                  [Type.atom("b"), Type.integer(2)],
                ]),
              ],
            ]),
          ]),
        ],
      ]);

      const operation = Operation.fromSpecDom(
        specDom,
        defaultTarget,
        eventParam,
      );

      assert.deepStrictEqual(
        operation,
        Type.actionStruct({
          name: Type.atom("my_action"),
          params: Type.map([
            [Type.atom("a"), Type.integer(1)],
            [Type.atom("b"), Type.integer(2)],
            [Type.atom("event"), eventParam],
          ]),
          target: defaultTarget,
        }),
      );
    });

    it("multiple chunks", () => {
      // Example: $click="aaa{123}bbb"
      // Spec DOM: [text: "aaa", expression: {123}, text: "bbb"],
      // which is equivalent to [{:text, "aaa"}, {:expression, {123}}, {:text, "bbb"}]
      const specDom = Type.keywordList([
        [Type.atom("text"), Type.bitstring("aaa")],
        [Type.atom("expression"), Type.tuple([Type.integer(123)])],
        [Type.atom("text"), Type.bitstring("bbb")],
      ]);

      const operation = Operation.fromSpecDom(
        specDom,
        defaultTarget,
        eventParam,
      );

      assert.deepStrictEqual(
        operation,
        Type.actionStruct({
          name: Type.atom("aaa123bbb"),
          params: Type.map([[Type.atom("event"), eventParam]]),
          target: defaultTarget,
        }),
      );
    });
  });

  describe("isAction()", () => {
    it("action", () => {
      const action = Type.actionStruct({
        name: Type.atom("my_action"),
        params: Type.map(),
        target: Type.bitstring("my_target"),
      });

      assert.isTrue(Operation.isAction(action));
    });

    it("command", () => {
      const command = Type.commandStruct({
        name: Type.atom("my_command"),
        params: Type.map(),
        target: Type.bitstring("my_target"),
      });

      assert.isFalse(Operation.isAction(command));
    });
  });
});
