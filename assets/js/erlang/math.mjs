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
      Interpreter.raiseBifError("badarg", "math", "ceil", [number]);
    }

    return Type.isInteger(number)
      ? Type.float(Number(number.value))
      : Type.float(Math.ceil(number.value));
  },
  // End ceil/1
  // Deps: []

  // Start exp/1
  "exp/1": (number) => {
    if (!Type.isNumber(number)) {
      Interpreter.raiseBifError("badarg", "math", "exp", [number]);
    }

    const value = Type.isInteger(number) ? Number(number.value) : number.value;
    const result = Math.exp(value);

    if (!Number.isFinite(result)) {
      Interpreter.raiseBifError("badarith", "math", "exp", [number]);
    }

    return Type.float(result);
  },
  // End exp/1
  // Deps: []

  // Start floor/1
  "floor/1": (number) => {
    if (!Type.isNumber(number)) {
      Interpreter.raiseBifError("badarg", "math", "floor", [number]);
    }
    return Type.isInteger(number)
      ? Type.float(Number(number.value))
      : Type.float(Math.floor(number.value));
  },
  // End floor/1
  // Deps: []

  // Start log/1
  "log/1": (number) => {
    if (!Type.isNumber(number)) {
      Interpreter.raiseBifError("badarg", "math", "log", [number]);
    }

    const value = Type.isInteger(number) ? Number(number.value) : number.value;

    if (value <= 0) {
      Interpreter.raiseBifError("badarith", "math", "log", [number]);
    }

    return Type.float(Math.log(value));
  },
  // End log/1
  // Deps: []

  // Start pow/2
  "pow/2": (base, exponent) => {
    if (!Type.isNumber(base) || !Type.isNumber(exponent)) {
      Interpreter.raiseBifError("badarg", "math", "pow", [base, exponent]);
    }

    const exponentValue = Number(exponent.value);
    const hasFractionalPart = exponentValue % 1 !== 0;

    if (base.value < 0 && hasFractionalPart) {
      Interpreter.raiseBifError("badarith", "math", "pow", [base, exponent]);
    }

    return Type.float(Math.pow(Number(base.value), exponentValue));
  },
  // End pow/2
  // Deps: []
};

export default Erlang_Math;
