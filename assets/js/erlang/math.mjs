"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// NOTE!
// BigInt values are similar to Number values in some ways, but also differ in a few key matters: A BigInt value cannot
// be used with methods in the built-in Math object and cannot be mixed with a Number value in operations; they must be
// coerced to the same type. Be careful coercing values back and forth, however, as the precision of a BigInt value may
// be lost when it is coerced to a Number value.
// re: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/BigInt

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

  // Start pow/2
  "pow/2": (number, exponent) => {
    if (!Type.isNumber(number)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    }

    if (!Type.isNumber(exponent)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a number"),
      );
    }

    if (number.value < 0 && Type.isFloat(exponent)) {
      Interpreter.raiseArithmeticError();
    }

    return Type.float(Math.pow(Number(number.value), Number(exponent.value)));
  },
  // End pow/2
  // Deps: []
};

export default Erlang_Math;
