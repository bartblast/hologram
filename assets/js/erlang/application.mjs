"use strict";

import ERTS from "../erts.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Application = {
  // The application a module belongs to is read from the metadata its bundle
  // registered, which happens only when client stacktraces are enabled. A module
  // with no entry - a ported Erlang module, or any module at all when the
  // setting is off - is :undefined here, the same answer the BEAM gives for a
  // module it can't place.
  // Start get_application/1
  "get_application/1": (module) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseFunctionClauseError(
        "application",
        "get_application",
        1,
        [module],
      );
    }

    const app = ERTS.moduleMetadata[Interpreter.moduleExName(module)]?.app;

    return typeof app === "undefined"
      ? Type.atom("undefined")
      : Type.tuple([Type.atom("ok"), Type.atom(app)]);
  },
  // End get_application/1
  // Deps: []

  // Only :vsn is answered - the client carries each application's version, but
  // none of the rest of its specification. Every other key is :undefined, which
  // is what the BEAM answers for a key an application doesn't define, and for
  // an application it doesn't know at all.
  // Start get_key/2
  "get_key/2": (app, key) => {
    if (!Type.isAtom(app) || !Type.isAtom(key) || key.value !== "vsn") {
      return Type.atom("undefined");
    }

    const vsn = ERTS.appVersions[app.value];

    return typeof vsn === "undefined"
      ? Type.atom("undefined")
      : Type.tuple([Type.atom("ok"), Type.charlist(vsn)]);
  },
  // End get_key/2
  // Deps: []
};

export default Erlang_Application;
