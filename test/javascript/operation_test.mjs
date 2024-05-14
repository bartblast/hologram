"use strict";

import {assert, linkModules, unlinkModules} from "./support/helpers.mjs";

import HologramInterpreterError from "../../assets/js/errors/interpreter_error.mjs";
import Operation from "../../assets/js/operation.mjs";
import Type from "../../assets/js/type.mjs";

const defaultTarget = Type.bitstring("my_default_target");
const eventParam = "my_event_param";

describe("Operation", () => {
  before(() => linkModules());
  after(() => unlinkModules());

  describe("constructor()", () => {
    it("single text chunk", () => {
      // "my_action"
      const specDom = Type.keywordList([
        [Type.atom("text"), Type.bitstring("my_action")],
      ]);

      const operation = new Operation(specDom, defaultTarget, eventParam);

      assert.deepStrictEqual(operation.name, Type.atom("my_action"));

      assert.deepStrictEqual(
        operation.params,
        Type.map([[Type.atom("event"), eventParam]]),
      );

      assert.deepStrictEqual(operation.target, defaultTarget);
      assert.deepStrictEqual(operation.type, Type.atom("action"));
    });

    it("single expression chunk, shorthand syntax, no params", () => {
      // {:my_action}
      const specDom = Type.keywordList([
        [Type.atom("expression"), Type.tuple([Type.atom("my_action")])],
      ]);

      const operation = new Operation(specDom, defaultTarget, eventParam);

      assert.deepStrictEqual(operation.name, Type.atom("my_action"));

      assert.deepStrictEqual(
        operation.params,
        Type.map([[Type.atom("event"), eventParam]]),
      );

      assert.deepStrictEqual(operation.target, defaultTarget);
      assert.deepStrictEqual(operation.type, Type.atom("action"));
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

      const operation = new Operation(specDom, defaultTarget, eventParam);

      assert.deepStrictEqual(operation.name, Type.atom("my_action"));
      assert.deepStrictEqual(operation.target, defaultTarget);
      assert.deepStrictEqual(operation.type, Type.atom("action"));

      assert.deepStrictEqual(
        operation.params,
        Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
          [Type.atom("event"), eventParam],
        ]),
      );
    });

    it("single expression chunk, longhand syntax, action (by default), no params, default target", () => {
      // {name: :my_action}
      const specDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([[Type.atom("name"), Type.atom("my_action")]]),
          ]),
        ],
      ]);

      const operation = new Operation(specDom, defaultTarget, eventParam);

      assert.deepStrictEqual(operation.name, Type.atom("my_action"));

      assert.deepStrictEqual(
        operation.params,
        Type.map([[Type.atom("event"), eventParam]]),
      );

      assert.deepStrictEqual(operation.target, defaultTarget);
      assert.deepStrictEqual(operation.type, Type.atom("action"));
    });

    it("single expression chunk, longhand syntax, command, no params, default target", () => {
      // {name: :my_command, type: :command}
      const specDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([
              [Type.atom("name"), Type.atom("my_command")],
              [Type.atom("type"), Type.atom("command")],
            ]),
          ]),
        ],
      ]);

      const operation = new Operation(specDom, defaultTarget, eventParam);

      assert.deepStrictEqual(operation.name, Type.atom("my_command"));

      assert.deepStrictEqual(
        operation.params,
        Type.map([[Type.atom("event"), eventParam]]),
      );

      assert.deepStrictEqual(operation.target, defaultTarget);
      assert.deepStrictEqual(operation.type, Type.atom("command"));
    });

    it("single expression chunk, longhand syntax, target specified", () => {
      const target = Type.bitstring("my_target");

      // {name: :my_action, target: "my_target"}
      const specDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([
              [Type.atom("name"), Type.atom("my_action")],
              [Type.atom("target"), target],
            ]),
          ]),
        ],
      ]);

      const operation = new Operation(specDom, target, eventParam);

      assert.deepStrictEqual(operation.target, target);
    });

    it("single expression chunk, longhand syntax, with params", () => {
      // {name: :my_action, params: [a: 1, b: 2]}
      const specDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([
              [Type.atom("name"), Type.atom("my_action")],
              [
                Type.atom("params"),
                Type.keywordList([
                  [Type.atom("a"), Type.integer(1)],
                  [Type.atom("b"), Type.integer(2)],
                ]),
              ],
            ]),
          ]),
        ],
      ]);

      const operation = new Operation(specDom, defaultTarget, eventParam);

      assert.deepStrictEqual(
        operation.params,
        Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.integer(2)],
          [Type.atom("event"), eventParam],
        ]),
      );
    });

    it("multiple chunks", () => {
      "aaa{123}bbb";
      const specDom = Type.keywordList([
        [Type.atom("text"), Type.bitstring("aaa")],
        [Type.atom("expression"), Type.tuple([Type.integer(123)])],
        [Type.atom("text"), Type.bitstring("bbb")],
      ]);

      const operation = new Operation(specDom, defaultTarget, eventParam);

      assert.deepStrictEqual(operation.name, Type.atom("aaa123bbb"));

      assert.deepStrictEqual(
        operation.params,
        Type.map([[Type.atom("event"), eventParam]]),
      );

      assert.deepStrictEqual(operation.target, defaultTarget);
      assert.deepStrictEqual(operation.type, Type.atom("action"));
    });

    it("invalid operation spec", () => {
      // {params: [a: 1, b: 2]}
      const specDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([
              [
                Type.atom("params"),
                Type.keywordList([
                  [Type.atom("a"), Type.integer(1)],
                  [Type.atom("b"), Type.integer(2)],
                ]),
              ],
            ]),
          ]),
        ],
      ]);

      assert.throw(
        () => new Operation(specDom, defaultTarget, eventParam),
        HologramInterpreterError,
        `Operation spec is invalid: "{[params: [a: 1, b: 2]]}". See what to do here: https://www.hologram.page/TODO`,
      );
    });
  });
});
