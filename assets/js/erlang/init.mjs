"use strict";

import MemoryStorage from "../memory_storage.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Init = {
  // Start get_argument/1
  "get_argument/1": (flag) => {
    if (!Type.isAtom(flag)) {
      return Type.atom("error");
    }

    const scopedKey = Type.tuple([Type.atom("init_argument"), flag]);
    const value = MemoryStorage.get(Type.encodeMapKey(scopedKey));

    if (value === null) {
      return Type.atom("error");
    }

    return Type.tuple([Type.atom("ok"), value]);
  },
  // End get_argument/1
  // Deps: []
};

export default Erlang_Init;
