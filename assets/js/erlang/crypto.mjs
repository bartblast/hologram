"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Crypto = {
  // Start hash/2
  "hash/2": async (algorithm, data) => {
    if (!Type.isAtom(algorithm)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // In browser context, we would use Web Crypto API
    // However, this needs to be async which doesn't match Erlang's sync behavior
    // For now, raise an error
    Interpreter.raiseArgumentError(
      "crypto:hash/2 is not supported in client-side Hologram runtime. " +
      "Cryptographic operations should be performed server-side."
    );
  },
  // End hash/2
  // Deps: []

  // Start strong_rand_bytes/1
  "strong_rand_bytes/1": (n) => {
    if (!Type.isInteger(n)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    const num = Number(n.value);

    if (num < 0) {
      Interpreter.raiseArgumentError("argument error");
    }

    // Use Web Crypto API if available
    if (typeof crypto !== "undefined" && crypto.getRandomValues) {
      const bytes = new Uint8Array(num);
      crypto.getRandomValues(bytes);
      return Type.bitstring(bytes, 0);
    }

    // Fallback to Math.random (not cryptographically secure!)
    const bytes = new Uint8Array(num);
    for (let i = 0; i < num; i++) {
      bytes[i] = Math.floor(Math.random() * 256);
    }
    return Type.bitstring(bytes, 0);
  },
  // End strong_rand_bytes/1
  // Deps: []

  // Start mac/3
  "mac/3": (type, key, data) => {
    if (!Type.isAtom(type)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // HMAC operations require async Web Crypto API
    Interpreter.raiseArgumentError(
      "crypto:mac/3 is not supported in client-side Hologram runtime."
    );
  },
  // End mac/3
  // Deps: []

  // Start mac/4
  "mac/4": (type, subType, key, data) => {
    if (!Type.isAtom(type)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    Interpreter.raiseArgumentError(
      "crypto:mac/4 is not supported in client-side Hologram runtime."
    );
  },
  // End mac/4
  // Deps: []
};

export default Erlang_Crypto;
