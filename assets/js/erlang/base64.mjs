"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Base64 = {
  // Start encode/1
  "encode/1": (data) => {
    if (!Type.isBinary(data)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    try {
      Bitstring.maybeSetBytesFromText(data);

      // Convert Uint8Array to base64 string
      let binaryString = "";
      const bytes = data.bytes;
      for (let i = 0; i < bytes.length; i++) {
        binaryString += String.fromCharCode(bytes[i]);
      }

      const base64String = btoa(binaryString);

      // Convert to binary
      const encoder = new TextEncoder();
      const encoded = encoder.encode(base64String);
      return Type.bitstring(encoded, 0);
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End encode/1
  // Deps: []

  // Start decode/1
  "decode/1": (data) => {
    if (!Type.isBinary(data)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    try {
      Bitstring.maybeSetBytesFromText(data);

      // Convert binary to string
      const decoder = new TextDecoder("utf-8");
      const base64String = decoder.decode(data.bytes);

      // Decode base64
      const binaryString = atob(base64String);

      // Convert to Uint8Array
      const bytes = new Uint8Array(binaryString.length);
      for (let i = 0; i < binaryString.length; i++) {
        bytes[i] = binaryString.charCodeAt(i);
      }

      return Type.bitstring(bytes, 0);
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End decode/1
  // Deps: []

  // Start encode_to_string/1
  "encode_to_string/1": (data) => {
    if (!Type.isBinary(data)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    try {
      Bitstring.maybeSetBytesFromText(data);

      // Convert Uint8Array to base64 string
      let binaryString = "";
      const bytes = data.bytes;
      for (let i = 0; i < bytes.length; i++) {
        binaryString += String.fromCharCode(bytes[i]);
      }

      const base64String = btoa(binaryString);

      // Convert to character list
      const chars = [...base64String].map((char) =>
        Type.integer(char.charCodeAt(0))
      );
      return Type.list(chars);
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End encode_to_string/1
  // Deps: []

  // Start decode_to_string/1
  "decode_to_string/1": (data) => {
    // In Erlang, this decodes base64 to a string (charlist)
    try {
      let base64String;

      if (Type.isBinary(data)) {
        Bitstring.maybeSetBytesFromText(data);
        const decoder = new TextDecoder("utf-8");
        base64String = decoder.decode(data.bytes);
      } else if (Type.isList(data)) {
        // Convert charlist to string
        base64String = data.data.map((elem) =>
          String.fromCharCode(Number(elem.value))
        ).join("");
      } else {
        Interpreter.raiseArgumentError("argument error");
        return;
      }

      // Decode base64
      const binaryString = atob(base64String);

      // Convert to character list
      const chars = [...binaryString].map((char) =>
        Type.integer(char.charCodeAt(0))
      );
      return Type.list(chars);
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End decode_to_string/1
  // Deps: []

  // Start mime_decode/1
  "mime_decode/1": (data) => {
    // MIME decode is similar to regular decode but strips whitespace
    if (!Type.isBinary(data)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    try {
      Bitstring.maybeSetBytesFromText(data);

      // Convert binary to string and strip whitespace
      const decoder = new TextDecoder("utf-8");
      let base64String = decoder.decode(data.bytes);
      base64String = base64String.replace(/\s+/g, "");

      // Decode base64
      const binaryString = atob(base64String);

      // Convert to Uint8Array
      const bytes = new Uint8Array(binaryString.length);
      for (let i = 0; i < binaryString.length; i++) {
        bytes[i] = binaryString.charCodeAt(i);
      }

      return Type.bitstring(bytes, 0);
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End mime_decode/1
  // Deps: []

  // Start mime_decode_to_string/1
  "mime_decode_to_string/1": (data) => {
    try {
      let base64String;

      if (Type.isBinary(data)) {
        Bitstring.maybeSetBytesFromText(data);
        const decoder = new TextDecoder("utf-8");
        base64String = decoder.decode(data.bytes);
      } else if (Type.isList(data)) {
        base64String = data.data.map((elem) =>
          String.fromCharCode(Number(elem.value))
        ).join("");
      } else {
        Interpreter.raiseArgumentError("argument error");
        return;
      }

      // Strip whitespace
      base64String = base64String.replace(/\s+/g, "");

      // Decode base64
      const binaryString = atob(base64String);

      // Convert to character list
      const chars = [...binaryString].map((char) =>
        Type.integer(char.charCodeAt(0))
      );
      return Type.list(chars);
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End mime_decode_to_string/1
  // Deps: []
};

export default Erlang_Base64;
