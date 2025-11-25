"use strict";

import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Re = {
  // Start version/0
  "version/0": () => {
    // TODO: Replace hardcoded PCRE version with version captured from system at runtime
    return Type.bitstring("8.44 2020-02-12");
  },
  // End version/0
  // Deps: []
};

export default Erlang_Re;
