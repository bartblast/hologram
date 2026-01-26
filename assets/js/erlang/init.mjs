"use strict";

import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Init = {
  // Note: The JS implementation returns hardcoded values for security reasons:
  // - :home returns {:ok, [[~c"/"]]}
  // - :progname returns {:ok, [[~c"hologram"]]}
  // - :root returns {:ok, [[~c"/"]]}
  // - Any other flag returns :error
  // Start get_argument/1
  "get_argument/1": (flag) => {
    if (!Type.isAtom(flag)) {
      return Type.atom("error");
    }

    const flagValue = flag.value;

    if (flagValue === "home") {
      return Type.tuple([
        Type.atom("ok"),
        Type.list([Type.list([Type.charlist("/")])]),
      ]);
    }

    if (flagValue === "progname") {
      return Type.tuple([
        Type.atom("ok"),
        Type.list([Type.list([Type.charlist("hologram")])]),
      ]);
    }

    if (flagValue === "root") {
      return Type.tuple([
        Type.atom("ok"),
        Type.list([Type.list([Type.charlist("/")])]),
      ]);
    }

    return Type.atom("error");
  },
  // End get_argument/1
  // Deps: []
};

export default Erlang_Init;
