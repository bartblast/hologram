"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Uri_String = {
  // Start parse/1
  "parse/1": (uriString) => {
    // Helpers

    // Collects parsed pieces into a Hologram map, keeping Erlang port semantics (:undefined for empty port).
    const buildResultMap = (uri) => {
      const pairs = [];

      if (uri.scheme !== undefined) {
        pairs.push([Type.atom("scheme"), Type.bitstring(uri.scheme)]);
      }
      if (uri.userinfo !== undefined) {
        pairs.push([Type.atom("userinfo"), Type.bitstring(uri.userinfo)]);
      }
      if (uri.host !== undefined) {
        pairs.push([Type.atom("host"), Type.bitstring(uri.host)]);
      }
      if (uri.port !== undefined) {
        const portValue =
          uri.port === null ? Type.atom("undefined") : Type.integer(uri.port);
        pairs.push([Type.atom("port"), portValue]);
      }
      if (uri.path !== undefined) {
        pairs.push([Type.atom("path"), Type.bitstring(uri.path)]);
      }
      if (uri.query !== undefined) {
        pairs.push([Type.atom("query"), Type.bitstring(uri.query)]);
      }
      if (uri.fragment !== undefined) {
        pairs.push([Type.atom("fragment"), Type.bitstring(uri.fragment)]);
      }

      return Type.map(pairs);
    };

    // For list input, re-encode any binaries in the result back into charlists.
    const convertBinaryFieldsToLists = (result) => {
      if (!Type.isMap(result)) return result;

      const listResult = [];
      for (const encodedKey of Object.keys(result.data)) {
        const [key, value] = result.data[encodedKey];
        if (Type.isBinary(value)) {
          Bitstring.maybeSetTextFromBytes(value);
          const codepoints = [...value.text].map((char) =>
            Type.integer(char.codePointAt(0)),
          );
          listResult.push([key, Type.list(codepoints)]);
        } else {
          listResult.push([key, value]);
        }
      }

      return Type.map(listResult);
    };

    // Validates and decodes an Erlang charlist into a JavaScript string; raises on invalid input (matches OTP failures).
    const decodeListToString = (list) => {
      let text = "";

      for (const item of list.data) {
        if (!Type.isInteger(item)) {
          Interpreter.raiseArgumentError(
            "errors were found at the given arguments:\n\n  * 1st argument: not valid character data (an iodata term)\n",
          );
        }

        const codepoint = Number(item.value);
        if (codepoint < 0 || codepoint > 1114111) {
          Interpreter.raiseFunctionClauseError(
            Interpreter.buildFunctionClauseErrorMsg(":uri_string.parse/1", [
              list,
            ]),
          );
        }

        text += String.fromCodePoint(codepoint);
      }

      return text;
    };

    // Ensures a binary is valid UTF-8; otherwise raises FunctionClauseError (OTP raises in parse_scheme_start/2).
    const ensureUtf8Binary = (binary) => {
      Bitstring.maybeSetTextFromBytes(binary);
      if (binary.text === false) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":uri_string.parse/1", [
            binary,
          ]),
        );
      }

      return binary.text;
    };

    const isError = (value) => Type.isTuple(value);

    // Parses the authority portion (//userinfo@host:port), including IPv6 [host] and empty ports.
    const parseAuthority = (state) => {
      if (!state.remaining.startsWith("//")) return state;

      const withoutSlashes = state.remaining.slice(2);
      const atIndex = withoutSlashes.indexOf("@");
      const slashIndex = withoutSlashes.search(/[/?#]/);
      const hasUserinfo =
        atIndex !== -1 && (slashIndex === -1 || atIndex < slashIndex);
      const userinfo = hasUserinfo
        ? withoutSlashes.slice(0, atIndex)
        : undefined;
      const afterUserinfo = hasUserinfo
        ? withoutSlashes.slice(atIndex + 1)
        : withoutSlashes;

      // Check for multiple @ symbols in the authority portion (before /, ?, or #).
      // Extract the authority portion (everything before /, ?, or #).
      const authorityEndIndex = afterUserinfo.search(/[/?#]/);
      const authorityPortion =
        authorityEndIndex === -1
          ? afterUserinfo
          : afterUserinfo.slice(0, authorityEndIndex);

      // If there's a @ in the authority portion after userinfo, it's invalid.
      // OTP payload differs depending on presence of scheme:
      // - With scheme (e.g., http://a@b@c/path) -> ':'
      // - Bare authority (e.g., //a@b@c/path)   -> '@'
      if (authorityPortion.includes("@")) {
        const payloadChar = state.uri.scheme ? 58 /* ':' */ : 64; /* '@' */
        return Type.tuple([
          Type.atom("error"),
          Type.atom("invalid_uri"),
          Type.list([Type.integer(payloadChar)]),
        ]);
      }

      const hasBracketHost = afterUserinfo.startsWith("[");
      const closeBracketIndex = hasBracketHost
        ? afterUserinfo.indexOf("]")
        : -1;
      if (hasBracketHost && closeBracketIndex === -1) {
        // OTP uses charlist(":") as the invalid_uri payload.
        return Type.tuple([
          Type.atom("error"),
          Type.atom("invalid_uri"),
          Type.list([Type.integer(58)]),
        ]);
      }

      if (hasBracketHost) {
        const host = afterUserinfo.slice(1, closeBracketIndex);
        const afterHost = afterUserinfo.slice(closeBracketIndex + 1);
        return parsePort(state.uri, userinfo, host, afterHost);
      }

      const endMatch = afterUserinfo.match(/^([^:/?#]*)(.*)/s);
      const host = endMatch[1];
      const afterHost = endMatch[2];
      return parsePort(state.uri, userinfo, host, afterHost);
    };

    const parseFragmentPart = (state) => {
      if (!state.remaining.startsWith("#")) return state;
      const fragment = state.remaining.slice(1);

      if (fragment.includes("#")) {
        // OTP uses charlist(":") as the invalid_uri payload.
        return Type.tuple([
          Type.atom("error"),
          Type.atom("invalid_uri"),
          Type.list([Type.integer(58)]),
        ]);
      }

      return {uri: {...state.uri, fragment}, remaining: ""};
    };

    // Keeps path when host is present or path is non-empty; empty relative refs get path="".
    const parsePathPart = (state) => {
      const pathEndMatch = state.remaining.match(/^([^?#]*)(.*)/s);
      if (!pathEndMatch) return state;

      const path = pathEndMatch[1];
      const hasHost = state.uri.host !== undefined;
      const shouldSetPath = hasHost || path !== "";
      const isEmptyReference =
        !hasHost && path === "" && Object.keys(state.uri).length === 0;

      if (shouldSetPath) {
        return {uri: {...state.uri, path}, remaining: pathEndMatch[2]};
      }

      if (isEmptyReference) {
        return {uri: {...state.uri, path: ""}, remaining: pathEndMatch[2]};
      }

      return {uri: state.uri, remaining: pathEndMatch[2]};
    };

    // Adds port if present; empty port string becomes null so it renders as :undefined in the result map.
    const parsePort = (uri, userinfo, host, remaining) => {
      if (!remaining.startsWith(":")) {
        const newUri =
          userinfo === undefined ? {...uri, host} : {...uri, host, userinfo};
        return {uri: newUri, remaining};
      }

      const afterColon = remaining.slice(1);
      const digitMatch = afterColon.match(/^(\d+)/);
      const portStr = digitMatch ? digitMatch[1] : "";
      const portRemainder = digitMatch
        ? afterColon.slice(portStr.length)
        : afterColon;

      const isDelimiterStart =
        portRemainder === "" ||
        portRemainder.startsWith("/") ||
        portRemainder.startsWith("?") ||
        portRemainder.startsWith("#");

      if (portStr === "" && !isDelimiterStart) {
        // OTP uses charlist(":") as the invalid_uri payload.
        return Type.tuple([
          Type.atom("error"),
          Type.atom("invalid_uri"),
          Type.list([Type.integer(58)]),
        ]);
      }

      if (portStr === "") {
        const newUri =
          userinfo === undefined
            ? {...uri, host, port: null}
            : {...uri, host, port: null, userinfo};
        return {uri: newUri, remaining: portRemainder};
      }

      if (!isDelimiterStart) {
        // OTP uses charlist(":") as the invalid_uri payload.
        return Type.tuple([
          Type.atom("error"),
          Type.atom("invalid_uri"),
          Type.list([Type.integer(58)]),
        ]);
      }

      const port = parseInt(portStr, 10);
      const newUri =
        userinfo === undefined
          ? {...uri, host, port}
          : {...uri, host, port, userinfo};

      return {uri: newUri, remaining: portRemainder};
    };

    const parseQueryPart = (state) => {
      if (!state.remaining.startsWith("?")) return state;

      const withoutQuestion = state.remaining.slice(1);
      const queryEndMatch = withoutQuestion.match(/^([^#]*)(.*)/s);
      if (!queryEndMatch) return state;

      const query = queryEndMatch[1];
      return {uri: {...state.uri, query}, remaining: queryEndMatch[2]};
    };

    const parseSchemePart = (state) => {
      const schemeMatch = state.remaining.match(
        /^([a-zA-Z][a-zA-Z0-9+\-.]*):(.*)$/s,
      );
      if (!schemeMatch) return state;

      return {
        uri: {...state.uri, scheme: schemeMatch[1]},
        remaining: schemeMatch[2],
      };
    };

    // Runs the parsing pipeline in RFC 3986 order: scheme -> authority -> path -> query -> fragment.
    const parseUri = (text) => {
      const state0 = {uri: {}, remaining: text};

      const state1 = parseSchemePart(state0);
      const state2 = parseAuthority(state1);
      if (isError(state2)) return state2;

      const state3 = parsePathPart(state2);
      const state4 = parseQueryPart(state3);
      const state5 = parseFragmentPart(state4);
      if (isError(state5)) return state5;

      return buildResultMap(state5.uri);
    };

    // Main logic

    if (Type.isBinary(uriString)) {
      const text = ensureUtf8Binary(uriString);
      return parseUri(text);
    }

    if (Type.isList(uriString)) {
      const decoded = decodeListToString(uriString);
      const result = parseUri(decoded);
      return convertBinaryFieldsToLists(result);
    }

    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":uri_string.parse/1", [
        uriString,
      ]),
    );
  },
  // End parse/1
  // Deps: []
};

export default Erlang_Uri_String;
