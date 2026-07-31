"use strict";

import CallStack from "../erts/call_stack.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

export default class HologramBoxedError extends Error {
  // Set while an error is deriving its struct and message. Both run transpiled Elixir, which can
  // itself raise - a port that isn't in the bundle, a formatter that fails on the term it is
  // given. Deriving that inner error would run the same code and raise the same way, so
  // derivation is skipped while it is already under way: the inner error keeps the raw form it
  // arrived in, and the outer derivation fails with it rather than the two of them looping until
  // the JavaScript stack is exhausted. Actions run sequentially, so a single flag is enough - the
  // same reasoning the shadow call stack rests on.
  static #isDeriving = false;

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

    // The two parts the display message is composed of: what was raised (the
    // exception module, or the kind for a throw or an exit) and what it says
    // about itself. Both are kept so a reporter can name the error without
    // deriving it a second time - a derivation that could fault where the
    // first one didn't, since it would run outside the guards below.
    Object.defineProperty(this, "type", {
      value: null,
      writable: true,
      configurable: true,
    });
    Object.defineProperty(this, "messageText", {
      value: null,
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

      // blamedStruct carries the same exception in its display form - what
      // rescue sees and what an error report shows differ, since blame/2
      // callbacks refine the struct against the stacktrace.
      Object.defineProperty(this, "blamedStruct", {
        value: null,
        writable: true,
        configurable: true,
      });

      this.rederive(Type.list());
    } else {
      this.type = kind.value;
      this.messageText = Interpreter.inspect(value);
      this.message = `(${this.type}) ${this.messageText}`;
    }
  }

  // Re-derives the normalized struct, its blamed counterpart and the display
  // message using the given boxed stacktrace. Both derivations may depend on
  // the raising frame's args and error_info, which :erlang.error/3 attaches
  // only after construction.
  rederive(boxedStacktrace) {
    if (this.kind.value !== "error") {
      return;
    }

    if (HologramBoxedError.#isDeriving) {
      this.#takeRawForm();
      return;
    }

    HologramBoxedError.#isDeriving = true;

    try {
      this.struct = Interpreter.normalizeError(this.value, boxedStacktrace);
      this.blamedStruct = Interpreter.blameError(this.value, boxedStacktrace);

      this.type = Interpreter.getErrorType(this);
      this.messageText = Interpreter.resolveErrorMessage(this.blamedStruct);

      this.message = `(${this.type}) ${this.messageText}`;
    } catch (error) {
      // A boxed error means the derivation raised the way Elixir code does, and it names what is
      // wrong better than this error could - it is carried out, having already taken its raw form
      // above. Anything else is the derivation machinery itself faulting, which must not cost the
      // caller the error they raised: they keep it in its raw form, with the fault named alongside
      // so it doesn't pass unnoticed.
      if (error instanceof HologramBoxedError) {
        throw error;
      }

      this.#takeRawForm(error);
    } finally {
      // Reset even when the derivation raises, so the error carrying that raise out still derives.
      HologramBoxedError.#isDeriving = false;
    }
  }

  // The error as it arrived, with no Elixir run to refine it: an exception struct stands as its
  // own normalized and blamed form, a bare reason has neither, and the message states what was
  // raised instead of what the exception would have said about itself. A derivation error is the
  // fault that stopped the refining, named so it isn't swallowed.
  #takeRawForm(derivationError = null) {
    this.struct = Type.isStruct(this.value) ? this.value : null;
    this.blamedStruct = this.struct;

    this.type =
      this.struct === null
        ? "error"
        : Interpreter.inspect(this.struct.data["atom(__struct__)"][1]);

    const fault =
      derivationError === null
        ? ""
        : ` (message derivation failed: ${derivationError.message})`;

    this.messageText = `${Interpreter.inspect(this.value)}${fault}`;
    this.message = `(${this.type}) ${this.messageText}`;
  }
}
