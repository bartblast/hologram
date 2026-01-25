"use strict";

import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Os = {
  // Start type/0
  // Returns the hardcoded value {:unix, :web} as the code will only execute in a web context
  // Elixir / Erlang will use Unix style paths in any conditionals
  "type/0": () => {
    return Type.tuple([Type.atom("unix"), Type.atom("web")]);
  },
  // End type/0
  // Deps: []
};

export default Erlang_Os;
