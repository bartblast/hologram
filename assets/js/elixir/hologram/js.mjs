"use strict";

import Bitstring2 from "../../bitstring2.mjs";
import Interpreter from "../../interpreter.mjs";

const Elixir_Hologram_JS = {
  "exec/1": (code) => {
    return Interpreter.evaluateJavaScriptCode(Bitstring2.toText(code));
  },
};

export default Elixir_Hologram_JS;
