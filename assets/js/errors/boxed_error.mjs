"use strict";

import Interpreter from "../interpreter.mjs";

export default class HologramBoxedError extends Error {
  constructor(struct) {
    super("");

    this.name = "HologramBoxedError";
    this.struct = struct;

    const boxedType = Interpreter.getErrorType(this);
    const boxedMessage = Interpreter.getErrorMessage(this);

    this.message = `(${boxedType}) ${boxedMessage}`;
  }
}
