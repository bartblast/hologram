"use strict";

import Interpreter from "../../interpreter.mjs";

// TODO: replace the placeholder with the client-side check - it evaluates the entity type's
// compiled policy rules against the grant tuples synced to the local database and the session
// identity held by the runtime, so that call sites read the same on both tiers.
const Elixir_Hologram_Auth = {
  "can?/3": (_userOrId, _operation, _entity) => {
    Interpreter.raiseError(
      "RuntimeError",
      "can?/3 is not available on the client yet - call it from a command handler, which runs on the server",
    );
  },
};

export default Elixir_Hologram_Auth;
