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
      // value carries the raw reason; struct carries its normalized exception
      // form. Normalizing here means rescue always matches against a real
      // exception struct, even when the reason is a bare term like :badarg.
      const struct = Interpreter.normalizeError(value);

      Object.defineProperty(this, "struct", {
        value: struct,
        writable: true,
        configurable: true,
      });

      const boxedType = Interpreter.getErrorType(this);
      const boxedMessage = Interpreter.resolveErrorMessage(struct);

      this.message = `(${boxedType}) ${boxedMessage}`;
    } else {
      this.message = `(${kind.value}) ${Interpreter.inspect(value)}`;
    }
  }
}
