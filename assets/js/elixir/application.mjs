"use strict";

import ERTS from "../erts.mjs";

const Elixir_Application = {
  // TODO: provide a more complete implementation.
  // Simplified temporary implementation - reads from client-side application env storage.
  "get_env/3": (app, key, defaultValue) => {
    return ERTS.applicationEnv.get(app, key, defaultValue);
  },
};

export default Elixir_Application;
