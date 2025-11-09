"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Elixir_URI = {
  "encode/2": function (string, predicate) {
    // Make it consistent with encode/2 guards: when is_binary(string) and is_function(predicate, 1)
    if (
      !Type.isBinary(string) ||
      !Type.isAnonymousFunction(predicate) ||
      predicate.arity !== 1
    ) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg("URI.encode/2", arguments),
      );
    }

    // Ensure bytes are available from the bitstring
    Bitstring.maybeSetBytesFromText(string);
    const bytes = string.bytes;

    // Check if predicate is &URI.char_unreserved?/1
    const isCharUnreservedPredicate =
      predicate.capturedModule === "URI" &&
      predicate.capturedFunction === "char_unreserved?";

    let result = "";

    // Process each byte
    for (let i = 0; i < bytes.length; i++) {
      const byte = bytes[i];
      let shouldEncode;

      if (isCharUnreservedPredicate) {
        // Fast path: manually check if byte is unreserved
        // Unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
        // character in ?0..?9 or character in ?a..?z or character in ?A..?Z or character in ~c"~_-."
        // prettier-ignore
        shouldEncode = !(
          (byte >= 65 && byte <= 90) ||   // A-Z
          (byte >= 97 && byte <= 122) ||  // a-z
          (byte >= 48 && byte <= 57) ||   // 0-9
          byte === 45 ||                  // -
          byte === 46 ||                  // .
          byte === 95 ||                  // _
          byte === 126                    // ~
        );
      } else {
        // Generic path: apply predicate to each byte

        const predicateResult = Interpreter.callAnonymousFunction(predicate, [
          Type.integer(byte),
        ]);

        shouldEncode = !Type.isTrue(predicateResult);
      }

      if (shouldEncode) {
        // Encode as percent-encoded hex
        const hex = byte.toString(16).toUpperCase().padStart(2, "0");
        result += `%${hex}`;
      } else {
        // Keep byte as-is (convert back to character)
        result += String.fromCharCode(byte);
      }
    }

    return Type.bitstring(result);
  },
};

export default Elixir_URI;
