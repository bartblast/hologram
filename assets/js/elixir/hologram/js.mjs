"use strict";

import Bitstring from "../../bitstring.mjs";
import Interpreter from "../../interpreter.mjs";

const Elixir_Hologram_JS = {
  "exec/1": (code) => {
    return Interpreter.evaluateJavaScriptCode(Bitstring.toText(code));
  },
};

export default Elixir_Hologram_JS;
