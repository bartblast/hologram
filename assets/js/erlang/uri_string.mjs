"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

function toString(input) {
  if (Type.isBinary(input)) {
    Bitstring.maybeSetBytesFromText(input);
    return new TextDecoder("utf-8").decode(input.bytes);
  } else if (Type.isList(input)) {
    const chars = input.data.map((elem) => {
      if (!Type.isInteger(elem)) {
        throw new Error("not a valid string");
      }
      return String.fromCharCode(Number(elem.value));
    });
    return chars.join("");
  } else {
    throw new Error("not a valid string");
  }
}

function toBinary(str) {
  const bytes = new TextEncoder().encode(str);
  return Type.bitstring(bytes, 0);
}

const Erlang_Uri_String = {
  // Start parse/1
  "parse/1": (uriString) => {
    try {
      const uriStr = toString(uriString);

      // Use browser URL API to parse the URI
      try {
        const url = new URL(uriStr);

        const result = {};

        // Add scheme
        if (url.protocol) {
          const scheme = url.protocol.replace(":", "");
          result[Type.encodeMapKey(Type.atom("scheme"))] = [
            Type.atom("scheme"),
            toBinary(scheme),
          ];
        }

        // Add host
        if (url.hostname) {
          result[Type.encodeMapKey(Type.atom("host"))] = [
            Type.atom("host"),
            toBinary(url.hostname),
          ];
        }

        // Add port
        if (url.port) {
          result[Type.encodeMapKey(Type.atom("port"))] = [
            Type.atom("port"),
            Type.integer(parseInt(url.port)),
          ];
        }

        // Add path
        if (url.pathname) {
          result[Type.encodeMapKey(Type.atom("path"))] = [
            Type.atom("path"),
            toBinary(url.pathname),
          ];
        }

        // Add query
        if (url.search) {
          const query = url.search.startsWith("?") ? url.search.substring(1) : url.search;
          result[Type.encodeMapKey(Type.atom("query"))] = [
            Type.atom("query"),
            toBinary(query),
          ];
        }

        // Add fragment
        if (url.hash) {
          const fragment = url.hash.startsWith("#") ? url.hash.substring(1) : url.hash;
          result[Type.encodeMapKey(Type.atom("fragment"))] = [
            Type.atom("fragment"),
            toBinary(fragment),
          ];
        }

        // Add userinfo if present
        if (url.username || url.password) {
          const userinfo = url.password
            ? `${url.username}:${url.password}`
            : url.username;
          result[Type.encodeMapKey(Type.atom("userinfo"))] = [
            Type.atom("userinfo"),
            toBinary(userinfo),
          ];
        }

        return Type.map(Object.values(result));
      } catch (urlError) {
        // If URL parsing fails, try to parse as a relative URI
        const result = {};

        // Simple relative path parsing
        const hashIndex = uriStr.indexOf("#");
        const queryIndex = uriStr.indexOf("?");

        let path = uriStr;
        let query = "";
        let fragment = "";

        if (hashIndex !== -1) {
          fragment = uriStr.substring(hashIndex + 1);
          path = uriStr.substring(0, hashIndex);
        }

        if (queryIndex !== -1 && (hashIndex === -1 || queryIndex < hashIndex)) {
          query = uriStr.substring(queryIndex + 1, hashIndex !== -1 ? hashIndex : undefined);
          path = uriStr.substring(0, queryIndex);
        }

        if (path) {
          result[Type.encodeMapKey(Type.atom("path"))] = [
            Type.atom("path"),
            toBinary(path),
          ];
        }

        if (query) {
          result[Type.encodeMapKey(Type.atom("query"))] = [
            Type.atom("query"),
            toBinary(query),
          ];
        }

        if (fragment) {
          result[Type.encodeMapKey(Type.atom("fragment"))] = [
            Type.atom("fragment"),
            toBinary(fragment),
          ];
        }

        return Type.map(Object.values(result));
      }
    } catch (error) {
      Interpreter.raiseArgumentError("argument error");
    }
  },
  // End parse/1
  // Deps: []
};

export default Erlang_Uri_String;
