"use strict";

import Erlang from "../erlang/erlang.mjs";

// IMPORTANT!
// If the given ported Elixir function calls other Erlang functions, then list such dependencies in the "Deps" comment.
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Bitwise = {
  // Start &&&/2
  "&&&/2": (left, right) => {
    return Erlang["band/2"](left, right);
  },
  // End &&&/2
  // Deps: [:erlang.band/2]

  // Start <<</2
  "<<</2": (left, right) => {
    return Erlang["bsl/2"](left, right);
  },
  // End <<</2
  // Deps: [:erlang.bsl/2]

  // Start >>>/2
  ">>>/2": (left, right) => {
    return Erlang["bsr/2"](left, right);
  },
  // End >>>/2
  // Deps: [:erlang.bsr/2]

  // Start ^^^/2
  "^^^/2": (left, right) => {
    return Erlang["bxor/2"](left, right);
  },
  // End ^^^/2
  // Deps: [:erlang.bxor/2]

  // Start band/2
  "band/2": (left, right) => {
    return Erlang["band/2"](left, right);
  },
  // End band/2
  // Deps: [:erlang.band/2]

  // Start bnot/1
  "bnot/1": (value) => {
    return Erlang["bnot/1"](value);
  },
  // End bnot/1
  // Deps: [:erlang.bnot/1]

  // Start bor/2
  "bor/2": (left, right) => {
    return Erlang["bor/2"](left, right);
  },
  // End bor/2
  // Deps: [:erlang.bor/2]

  // Start bsl/2
  "bsl/2": (left, right) => {
    return Erlang["bsl/2"](left, right);
  },
  // End bsl/2
  // Deps: [:erlang.bsl/2]

  // Start bsr/2
  "bsr/2": (left, right) => {
    return Erlang["bsr/2"](left, right);
  },
  // End bsr/2
  // Deps: [:erlang.bsr/2]

  // Start bxor/2
  "bxor/2": (left, right) => {
    return Erlang["bxor/2"](left, right);
  },
  // End bxor/2
  // Deps: [:erlang.bxor/2]

  // Start |||/2
  "|||/2": (left, right) => {
    return Erlang["bor/2"](left, right);
  },
  // End |||/2
  // Deps: [:erlang.bor/2]

  // Start ~~~/1
  "~~~/1": (value) => {
    return Erlang["bnot/1"](value);
  },
  // End ~~~/1
  // Deps: [:erlang.bnot/1]
};

export default Bitwise;
