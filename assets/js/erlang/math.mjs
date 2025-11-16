"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Math = {
  // Start ceil/1
  "ceil/1": (number) => {
    if (!Type.isNumber(number)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    }

    const value = Number(number.value);
    return Type.float(Math.ceil(value));
  },
  // End ceil/1
  // Deps: []

  // Start exp/1
  "exp/1": (number) => {
    if (!Type.isNumber(number)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    }

    const value = Number(number.value);
    return Type.float(Math.exp(value));
  },
  // End exp/1
  // Deps: []

  // Start floor/1
  "floor/1": (number) => {
    if (!Type.isNumber(number)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    }

    const value = Number(number.value);
    return Type.float(Math.floor(value));
  },
  // End floor/1
  // Deps: []

  // Start log/1
  "log/1": (number) => {
    if (!Type.isNumber(number)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    }

    const value = Number(number.value);

    if (value <= 0) {
      Interpreter.raiseArgumentError("argument error");
    }

    return Type.float(Math.log(value));
  },
  // End log/1
  // Deps: []

  // Start pow/2
  "pow/2": (base, exponent) => {
    if (!Type.isNumber(base)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    }

    if (!Type.isNumber(exponent)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a number"),
      );
    }

    const baseValue = Number(base.value);
    const exponentValue = Number(exponent.value);

    return Type.float(Math.pow(baseValue, exponentValue));
  },
  // End pow/2
  // Deps: []
};

export default Erlang_Math;
