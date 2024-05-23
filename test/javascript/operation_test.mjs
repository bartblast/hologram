"use strict";

import {assert, linkModules, unlinkModules} from "./support/helpers.mjs";

import Operation from "../../assets/js/operation.mjs";
import Type from "../../assets/js/type.mjs";

const defaultTarget = Type.bitstring("my_default_target");
const eventParam = "my_event_param";

describe("Operation", () => {
  before(() => linkModules());
  after(() => unlinkModules());

  describe("fromSpecDom()", () => {
    it("single text chunk", () => {
      // "my_action"
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
      // {:my_action}
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
      // {:my_action, a: 1, b: 2}
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
      // {%Action{name: :my_action}}
      const specDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([Type.actionStruct({name: Type.atom("my_action")})]),
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
      // {%Command{name: :my_command}}
      const specDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([Type.commandStruct({name: Type.atom("my_command")})]),
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
      const target = Type.bitstring("my_target");

      // {%Action{name: :my_action, target: "my_target"}}
      const specDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.actionStruct({name: Type.atom("my_action"), target: target}),
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
          target: target,
        }),
      );
    });

    it("single expression chunk, longhand syntax, with params", () => {
      // {%Action{name: :my_action, params: %{a: 1, b: 2}}}
      const specDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.actionStruct({
              name: Type.atom("my_action"),
              params: Type.map([
                [Type.atom("a"), Type.integer(1)],
                [Type.atom("b"), Type.integer(2)],
              ]),
            }),
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
      // "aaa{123}bbb";
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
