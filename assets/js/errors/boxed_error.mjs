"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

export default class HologramBoxedError extends Error {
  constructor(value, kind = Type.atom("error")) {
    super("");

    this.name = "HologramBoxedError";

    // kind, value and struct are internal carriers read by the try/rescue/catch
    // machinery. They are defined as non-enumerable because extra enumerable
    // own-properties on a thrown Error blank out the message that the browser's
    // uncaught-error reporting surfaces (and that Wallaby/chromedriver capture).
    Object.defineProperty(this, "kind", {
      value: kind,
      writable: true,
      configurable: true,
    });
    Object.defineProperty(this, "value", {
      value: value,
      writable: true,
      configurable: true,
    });

    if (kind.value === "error") {
      Object.defineProperty(this, "struct", {
        value: value,
        writable: true,
        configurable: true,
      });

      const boxedType = Interpreter.getErrorType(this);
      const boxedMessage = Interpreter.resolveErrorMessage(value);

      this.message = `(${boxedType}) ${boxedMessage}`;
    } else {
      this.message = `(${kind.value}) ${Interpreter.inspect(value)}`;
    }
  }
}
