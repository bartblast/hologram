"use strict";

import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Elixir_Config = {
  // The server reads this from the compiler's configuration, where it can be swapped for a
  // tokenizer of the host language. The client carries the one Elixir ships with, since a bundle
  // is built for the language its source was written in.
  // Start identifier_tokenizer/0
  "identifier_tokenizer/0": () => Type.alias("String.Tokenizer"),
  // End identifier_tokenizer/0
  // Deps: []
};

export default Erlang_Elixir_Config;
