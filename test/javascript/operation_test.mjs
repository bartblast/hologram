"use strict";

import {assert, linkModules, unlinkModules} from "./support/helpers.mjs";

import HologramInterpreterError from "../../assets/js/errors/interpreter_error.mjs";
import Operation from "../../assets/js/operation.mjs";
import Type from "../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

describe("name", () => {
  it("single text chunk", () => {
    const specDom = Type.keywordList([
      [Type.atom("text"), Type.bitstring("my_action")],
    ]);

    const operation = new Operation(specDom);

    assert.deepStrictEqual(operation.name, Type.atom("my_action"));
  });

  it("single expression chunk, shorthand syntax", () => {
    const specDom = Type.keywordList([
      [Type.atom("expression"), Type.tuple([Type.atom("my_action")])],
    ]);

    const operation = new Operation(specDom);

    assert.deepStrictEqual(operation.name, Type.atom("my_action"));
  });

  it("single expression chunk, longhand syntax, action", () => {
    const specDom = Type.keywordList([
      [
        Type.atom("expression"),
        Type.tuple([
          Type.keywordList([
            [Type.atom("action"), Type.atom("my_action")],
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

    const operation = new Operation(specDom);

    assert.deepStrictEqual(operation.name, Type.atom("my_action"));
  });

  it("single expression chunk, longhand syntax, command", () => {
    const specDom = Type.keywordList([
      [
        Type.atom("expression"),
        Type.tuple([
          Type.keywordList([
            [Type.atom("command"), Type.atom("my_command")],
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

    const operation = new Operation(specDom);

    assert.deepStrictEqual(operation.name, Type.atom("my_command"));
  });

  it("multiple chunks", () => {
    const specDom = Type.keywordList([
      [Type.atom("text"), Type.bitstring("aaa")],
      [Type.atom("expression"), Type.tuple([Type.integer(123)])],
      [Type.atom("text"), Type.bitstring("bbb")],
    ]);

    const operation = new Operation(specDom);

    assert.deepStrictEqual(operation.name, Type.atom("aaa123bbb"));
  });

  it("invalid operation spec", () => {
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
      () => new Operation(specDom),
      HologramInterpreterError,
      `Operation spec is invalid: "{[params: [a: 1, b: 2]]}". See what to do here: https://www.hologram.page/TODO`,
    );
  });
});
