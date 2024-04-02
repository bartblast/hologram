"use strict";

import MemoryStorage from "../memory_storage.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in a "deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.Compiler.list_runtime_mfas/1.

const Erlang_Persistent_Term = {
  // start get/2
  "get/2": (key, defaultValue) => {
    const scopedKey = Type.tuple([Type.atom("persistent_term"), key]);
    return MemoryStorage.get(Type.encodeMapKey(scopedKey)) || defaultValue;
  },
  // end get/2
  // Deps: []
};

export default Erlang_Persistent_Term;
