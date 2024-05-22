"use strict";

// eslint-disable-next-line no-unused-vars
import Interpreter from "./interpreter.mjs";

// eslint-disable-next-line no-unused-vars
import Type from "./type.mjs";

// Implemented as a separate class to decrease the scope available to eval().
export default class CodeEvaluator {
  static evaluate(code) {
    return eval(code);
  }
}
