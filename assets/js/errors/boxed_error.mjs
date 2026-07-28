"use strict";

import CallStack from "../erts/call_stack.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

export default class HologramBoxedError extends Error {
  constructor(value, kind = Type.atom("error")) {
    super("");

    this.name = "HologramBoxedError";

    // kind, value, stacktrace and struct are internal carriers read by the
    // try/rescue/catch machinery. They are defined as non-enumerable because
    // extra enumerable own-properties on a thrown Error blank out the message
    // that the browser's uncaught-error reporting surfaces (and that
    // Wallaby/chromedriver capture).
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

    // Snapshotted at construction time, while the raising frame is still on
    // the call stack - the finally-popping in the dispatch wrappers unwinds
    // the stack as this error propagates.
    Object.defineProperty(this, "stacktrace", {
      value: CallStack.snapshot(),
      writable: true,
      configurable: true,
    });

    if (kind.value === "error") {
      // value carries the raw reason; struct carries its normalized exception
      // form. Normalizing here means rescue always matches against a real
      // exception struct, even when the reason is a bare term like :badarg.
      Object.defineProperty(this, "struct", {
        value: null,
        writable: true,
        configurable: true,
      });

      this.rederive(Type.list());
    } else {
      this.message = `(${kind.value}) ${Interpreter.inspect(value)}`;
    }
  }

  // Re-derives the normalized struct and display message using the given
  // boxed stacktrace. Message derivation may depend on the raising frame's
  // args and error_info, which :erlang.error/3 attaches only after
  // construction.
  rederive(boxedStacktrace) {
    if (this.kind.value !== "error") {
      return;
    }

    this.struct = Interpreter.normalizeError(this.value, boxedStacktrace);

    const boxedType = Interpreter.getErrorType(this);
    const boxedMessage = Interpreter.resolveErrorMessage(this.struct);

    this.message = `(${boxedType}) ${boxedMessage}`;
  }
}
