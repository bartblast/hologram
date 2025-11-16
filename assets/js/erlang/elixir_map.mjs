"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Elixir_Map = {
  // Start maybe_load_struct/5
  "maybe_load_struct/5": (map, keys, module, fun, context) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    // Check if the map has a __struct__ key
    const structKey = Type.encodeMapKey(Type.atom("__struct__"));

    if (map.data[structKey]) {
      const structModule = map.data[structKey][1];

      // If the struct module matches the provided module, it's already loaded
      if (Type.isAtom(structModule) && Type.isAtom(module)) {
        if (structModule.value === module.value) {
          return map;
        }
      }

      // Call the provided function to load/validate the struct
      if (Type.isAnonymousFunction(fun)) {
        return Interpreter.callAnonymousFunction(fun, [map, keys, structModule, context]);
      } else {
        // If no function provided, return the map as-is
        return map;
      }
    }

    // No __struct__ key, return the map as-is
    return map;
  },
  // End maybe_load_struct/5
  // Deps: []
};

export default Erlang_Elixir_Map;
