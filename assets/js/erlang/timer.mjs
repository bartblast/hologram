"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Timer = {
  // Start sleep/1
  "sleep/1": (time) => {
    if (!Type.isInteger(time)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    // In browser context, we can't actually block execution
    // This is a simplified version that returns ok immediately
    // In real Erlang, this would block for the specified milliseconds
    // For actual async behavior, users should use JavaScript's setTimeout
    return Type.atom("ok");
  },
  // End sleep/1
  // Deps: []

  // Start send_after/2
  "send_after/2": (time, message) => {
    if (!Type.isInteger(time)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    // In the client-side runtime, we don't have process messaging
    // Return a dummy timer reference
    // In server-side Erlang, this would schedule a message to be sent
    const timerRef = Type.tuple([
      Type.atom("timer_ref"),
      Type.integer(Math.floor(Math.random() * 1000000)),
    ]);

    return Type.tuple([Type.atom("ok"), timerRef]);
  },
  // End send_after/2
  // Deps: []

  // Start send_after/3
  "send_after/3": (time, pid, message) => {
    if (!Type.isInteger(time)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    // Similar to send_after/2, return a dummy timer reference
    const timerRef = Type.tuple([
      Type.atom("timer_ref"),
      Type.integer(Math.floor(Math.random() * 1000000)),
    ]);

    return Type.tuple([Type.atom("ok"), timerRef]);
  },
  // End send_after/3
  // Deps: []

  // Start send_interval/2
  "send_interval/2": (time, message) => {
    if (!Type.isInteger(time)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    // In the client-side runtime, we don't have process messaging
    // Return a dummy timer reference
    const timerRef = Type.tuple([
      Type.atom("timer_ref"),
      Type.integer(Math.floor(Math.random() * 1000000)),
    ]);

    return Type.tuple([Type.atom("ok"), timerRef]);
  },
  // End send_interval/2
  // Deps: []

  // Start send_interval/3
  "send_interval/3": (time, pid, message) => {
    if (!Type.isInteger(time)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    // Similar to send_interval/2, return a dummy timer reference
    const timerRef = Type.tuple([
      Type.atom("timer_ref"),
      Type.integer(Math.floor(Math.random() * 1000000)),
    ]);

    return Type.tuple([Type.atom("ok"), timerRef]);
  },
  // End send_interval/3
  // Deps: []
};

export default Erlang_Timer;
