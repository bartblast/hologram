"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

export default class HologramBoxedError extends Error {
  constructor(value, kind = Type.atom("error")) {
    super("");

    this.name = "HologramBoxedError";
    this.kind = kind;
    this.value = value;

    if (kind.value === "error") {
      this.struct = value;

      const boxedType = Interpreter.getErrorType(this);
      const boxedMessage = Interpreter.resolveErrorMessage(value);

      this.message = `(${boxedType}) ${boxedMessage}`;
    } else {
      this.message = `(${kind.value}) ${Interpreter.inspect(value)}`;
    }
  }
}
