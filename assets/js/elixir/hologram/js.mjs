"use strict";

import Interpreter from "../../interpreter.mjs";

const Elixir_Hologram_JS = {
  "exec/1": (code) => {
    return Interpreter.evaluateJavaScriptCode(code);
  },
};

export default Elixir_Hologram_JS;
