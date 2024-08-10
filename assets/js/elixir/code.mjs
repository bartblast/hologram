"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Elixir_Code = {
  // This function is simplified - it returns either {:module, MyModule} or {:error, :nofile}.
  // Deps: [:code.ensure_loaded/1]
  "ensure_compiled/1": (module) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg("Code.ensure_compiled/1", [
          module,
        ]),
      );
    }

    return Erlang_Code["ensure_loaded/1"](module);
  },
};

export default Elixir_Code;
