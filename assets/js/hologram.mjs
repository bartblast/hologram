"use strict";

import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";

export default class Hologram {
  static Interpreter = Interpreter;
  static Type = Type;

  static raiseKeyError(message) {
    return Interpreter.raiseError("KeyError", message);
  }
}
