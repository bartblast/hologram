"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Erlang_Integer_To_List = {
  // Start integer_to_list/1
  "integer_to_list/1": (integer) => {
    // Validate: must be an integer term
    if (!Type.isInteger(integer)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "expected an integer"),
      );
    }

    // Convert
    const text = integer.value.toString(); // base 10

    return Type.bitstring(text);
  },
  // End integer_to_list/1
  // Deps: []

  // Start integer_to_list/2
  "integer_to_list/2": (integer, base) => {
    // Validate first argument
    if (!Type.isInteger(integer)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "expected an integer"),
      );
    }

    // Validate second argument
    if (!Type.isInteger(base)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "expected an integer"),
      );
    }

    const baseValue = Number(base.value);

    // Validate base range 2..36
    if (baseValue < 2 || baseValue > 36) {
      Interpreter.raiseErlangError("badarg");
    }

    // Convert in given base
    const raw = integer.value.toString(baseValue);

    const text = raw.toUpperCase();

    return Type.bitstring(text);
  },
  // End integer_to_list/2
  // Deps: []
};

export default Erlang_Integer_To_List;
