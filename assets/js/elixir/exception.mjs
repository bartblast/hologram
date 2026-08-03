"use strict";

import Bitstring from "../bitstring.mjs";
import HologramInterpreterError from "../errors/interpreter_error.mjs";
import Stacktrace from "../stacktrace.mjs";
import Type from "../type.mjs";

// Renders a stacktrace as Elixir renders it. Ported rather than transpiled
// because the transpiled form costs milliseconds per frame - a frame is a
// handful of interpolations, and each one is a String.Chars dispatch several
// interpreted calls deep - and because the branch reading the calling process's
// own stacktrace pulls Process.info/2 and the whole Enumerable.slice family
// into every bundle for a call the client can't make.
//
// What each frame reads as is worked out in Stacktrace, which keeps the parts
// apart so the error overlay can tone them separately. Joining them in order is
// all this adds.
//
// IMPORTANT!
// Every shape rendered here is Elixir's. Each is held against what Elixir
// really renders in
// test/elixir/hologram/ex_js_consistency/elixir/exception_test.exs, whose cases
// are twinned by test/javascript/elixir/exception_test.mjs.
// Always update all three together.
const Elixir_Exception = {
  // Deps: [Macro.inspect_atom/3]
  "format_stacktrace/1": (stacktrace) => {
    // Elixir reads the calling process's own stacktrace when given none. The
    // client has no such stacktrace to read: what it keeps is a shadow call
    // stack of its own, which isn't the same thing and isn't what a caller
    // asking for this would get on the server.
    if (!Type.isList(stacktrace)) {
      throw new HologramInterpreterError(
        "Exception.format_stacktrace/1 needs a stacktrace on the client - the " +
          "one Elixir reads from the calling process when given none isn't " +
          "kept there. Pass __STACKTRACE__ or a stacktrace of your own.",
      );
    }

    if (stacktrace.data.length === 0) {
      return Bitstring.fromText("\n");
    }

    const entries = stacktrace.data.map((frame) => {
      const {app, location, running} = Stacktrace.frameParts(frame);

      return `${app}${location}${running}`;
    });

    return Bitstring.fromText(`    ${entries.join("\n    ")}\n`);
  },
};

export default Elixir_Exception;
