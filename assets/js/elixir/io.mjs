"use strict";

import HologramInterpreterError from "../errors/interpreter_error.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Elixir_IO = {
  // Deps: [IO.inspect/2]
  "inspect/1": (term) => {
    return Elixir_IO["inspect/2"](term, Type.keywordList());
  },

  // Deps: [IO.inspect/3]
  "inspect/2": (term, opts) => {
    return Elixir_IO["inspect/3"](Type.atom("stdio"), term, opts);
  },

  "inspect/3": function (device, term, opts) {
    if (!Type.isAtom(device) && !Type.isPid(device)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg("IO.inspect/3", arguments),
      );
    }

    if (Type.isPid(device) || !["stdio", "stderr"].includes(device.value)) {
      const inspectedDevice = Interpreter.inspect(device);

      throw new HologramInterpreterError(
        `device ${inspectedDevice} was attempted to be used on the client side (only :stdio and :stderr devices are available)"`,
      );
    }

    const output = Interpreter.inspect(term, opts);

    console.log(output + "\n");

    return term;
  },
};

export default Elixir_IO;
