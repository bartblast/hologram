"use strict";

import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Os = {
  // Start type/0
  // Hardcoded {:unix, :web} - unlike Erlang, Hologram runtime is sandboxed from the underlying OS.
  // Web conventions are closest to :unix (paths, etc.); :web identifies browser/webview runtime.
  "type/0": () => {
    return Type.tuple([Type.atom("unix"), Type.atom("web")]);
  },
  // End type/0
  // Deps: []
};

export default Erlang_Os;
