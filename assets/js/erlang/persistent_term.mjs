"use strict";

import MemoryStorage from "../memory_storage.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Persistent_Term = {
  // Start get/2
  "get/2": (key, defaultValue) => {
    const scopedKey = Type.tuple([Type.atom("persistent_term"), key]);
    return MemoryStorage.get(Type.encodeMapKey(scopedKey)) || defaultValue;
  },
  // End get/2
  // Deps: []
};

export default Erlang_Persistent_Term;
