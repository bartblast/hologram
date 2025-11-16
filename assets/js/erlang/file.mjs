"use strict";

import Erlang_Filename from "./filename.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_File = {
  // Start basename/1
  "basename/1": (filename) => {
    // Delegate to filename module
    return Erlang_Filename["basename/1"](filename);
  },
  // End basename/1
  // Deps: [:filename.basename/1]

  // Start basename/2
  "basename/2": (filename, ext) => {
    // Delegate to filename module
    return Erlang_Filename["basename/2"](filename, ext);
  },
  // End basename/2
  // Deps: [:filename.basename/2]
};

export default Erlang_File;
