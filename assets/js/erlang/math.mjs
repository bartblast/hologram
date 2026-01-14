"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// NOTE: Math methods and BigInt incompatibility
// Hologram integers use BigInt internally, but JavaScript's Math methods cannot work with BigInt values.
// All numeric values must be converted to Number before passing to Math methods.
// Be aware that this conversion may lose precision for very large integers.

const Erlang_Math = {
  // Start ceil/1
  "ceil/1": (number) => {
    if (!Type.isNumber(number)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    }

    return Type.isInteger(number)
      ? Type.float(Number(number.value))
      : Type.float(Math.ceil(number.value));
  },
  // End ceil/1
  // Deps: []

  // Start floor/1
  "floor/1": (number) => {
    if (!Type.isNumber(number)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    }

    return Type.isInteger(number)
      ? Type.float(Number(number.value))
      : Type.float(Math.floor(number.value));
  },
  // End floor/1
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

    const exponentValue = Number(exponent.value);
    const hasFractionalPart = exponentValue % 1 !== 0;

    if (base.value < 0 && hasFractionalPart) {
      Interpreter.raiseArithmeticError();
    }

    return Type.float(Math.pow(Number(base.value), exponentValue));
  },
  // End pow/2
  // Deps: []
};

export default Erlang_Math;
