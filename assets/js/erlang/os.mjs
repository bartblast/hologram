"use strict";

import Erlang from "./erlang.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Os = {
  // Start system_time/0
  // See: docs/erlang_time_functions_porting_strategy.md
  "system_time/0": () => {
    // Date.now() returns milliseconds since Unix epoch.
    return Type.integer(BigInt(Date.now()) * 1_000_000n);
  },
  // End system_time/0
  // Deps: []

  // Start system_time/1
  // See: docs/erlang_time_functions_porting_strategy.md
  "system_time/1": (unit) => {
    if (!Erlang["_is_valid_time_unit/1"](unit)) {
      Interpreter.raiseBifError(
        "badarg",
        "os",
        "system_time",
        [unit],
        "erl_kernel_errors",
      );
    }
    const nativeTime = Erlang_Os["system_time/0"]();

    return Erlang["convert_time_unit/3"](nativeTime, Type.atom("native"), unit);
  },
  // End system_time/1
  // Deps: [:erlang._is_valid_time_unit/1, :erlang.convert_time_unit/3, :os.system_time/0]

  // Start type/0
  // Hardcoded {:unix, :web} - unlike Erlang, Hologram runtime is sandboxed from the underlying OS.
  // Web conventions are closest to :unix (paths, etc.); :web identifies browser/webview runtime.
  "type/0": () => {
    return Type.tuple([Type.atom("unix"), Type.atom("web")]);
  },
  // End type/0
  // Deps: []
};

export default Erlang_Os;
