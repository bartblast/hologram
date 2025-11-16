"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// Global registry for application environment variables
const applicationEnv = new Map();

const Erlang_Application = {
  // Start ensure_all_started/1
  "ensure_all_started/1": (application) => {
    const options = Type.atom("temporary");
    return Erlang_Application["ensure_all_started/2"](application, options);
  },
  // End ensure_all_started/1
  // Deps: [:application.ensure_all_started/2]

  // Start ensure_all_started/2
  "ensure_all_started/2": (application, type) => {
    if (!Type.isAtom(application)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isAtom(type)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    // In the browser/client context, applications are pre-loaded
    // Return success with empty list of started applications
    return Type.tuple([Type.atom("ok"), Type.list([])]);
  },
  // End ensure_all_started/2
  // Deps: []

  // Start ensure_all_started/3
  "ensure_all_started/3": (application, type, timeout) => {
    // Just delegate to ensure_all_started/2, timeout not relevant client-side
    return Erlang_Application["ensure_all_started/2"](application, type);
  },
  // End ensure_all_started/3
  // Deps: [:application.ensure_all_started/2]

  // Start ensure_started/2
  "ensure_started/2": (application, type) => {
    if (!Type.isAtom(application)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isAtom(type)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    // In the browser/client context, applications are pre-loaded
    return Type.atom("ok");
  },
  // End ensure_started/2
  // Deps: []

  // Start get_env/2
  "get_env/2": (application, key) => {
    if (!Type.isAtom(application)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isAtom(key)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    const appKey = `${application.value}:${key.value}`;

    if (applicationEnv.has(appKey)) {
      return Type.tuple([Type.atom("ok"), applicationEnv.get(appKey)]);
    }

    return Type.atom("undefined");
  },
  // End get_env/2
  // Deps: []

  // Start get_env/3
  "get_env/3": (application, key, defaultValue) => {
    if (!Type.isAtom(application)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isAtom(key)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    const appKey = `${application.value}:${key.value}`;

    if (applicationEnv.has(appKey)) {
      return applicationEnv.get(appKey);
    }

    return defaultValue;
  },
  // End get_env/3
  // Deps: []

  // Start get_key/2
  "get_key/2": (application, key) => {
    if (!Type.isAtom(application)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isAtom(key)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    // Common application keys
    const keyValue = key.value;

    switch (keyValue) {
      case "description":
        return Type.tuple([Type.atom("ok"), Type.bitstring("Hologram Application")]);
      case "vsn":
        return Type.tuple([Type.atom("ok"), Type.bitstring("0.1.0")]);
      case "modules":
        return Type.tuple([Type.atom("ok"), Type.list([])]);
      case "registered":
        return Type.tuple([Type.atom("ok"), Type.list([])]);
      case "applications":
        return Type.tuple([Type.atom("ok"), Type.list([])]);
      default:
        return Type.atom("undefined");
    }
  },
  // End get_key/2
  // Deps: []

  // Helper function to set environment variable (not part of standard API)
  "__setEnv__": (application, key, value) => {
    const appKey = `${application.value}:${key.value}`;
    applicationEnv.set(appKey, value);
  },
};

export default Erlang_Application;
