"use strict";

import {assert, linkModules, unlinkModules} from "./support/helpers.mjs";

import CodeEvaluator from "../../assets/js/code_evaluator.mjs";
import Type from "../../assets/js/type.mjs";

describe("CodeEvaluator", () => {
  before(() => linkModules());
  after(() => unlinkModules());

  it("evaluate()", () => {
    //  %{a: 1, b: 2}.a
    const code =
      'Interpreter.dotOperator(Type.map([[Type.atom("a"), Type.integer(1n)], [Type.atom("b"), Type.integer(2n)]]), Type.atom("a"))';

    const result = CodeEvaluator.evaluate(code);

    assert.deepStrictEqual(result, Type.integer(1));
  });
});
