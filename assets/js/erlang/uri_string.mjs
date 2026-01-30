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

    // Collects parsed pieces into a map.
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
          listResult.push([key, Type.charlist(value.text)]);
        } else {
          listResult.push([key, value]);
        }
      }

      return Type.map(listResult);
    };

    // TODO: use generic helper
    // Validates and decodes an Erlang charlist into a JavaScript string; raises on invalid input.
    const decodeListToString = (list) => {
      let text = "";

      for (const item of list.data) {
        if (!Type.isInteger(item)) {
          Interpreter.raiseArgumentError(
            Interpreter.buildArgumentErrorMsg(
              1,
              "not valid character data (an iodata term)",
            ),
          );
        }

        const codepoint = Number(item.value);

        if (codepoint < 0 || codepoint > 1114111) {
          Interpreter.raiseFunctionClauseError(
            Interpreter.buildFunctionClauseErrorMsg(
              ":uri_string.parse_scheme_start/2",
              [
                Type.tuple([Type.atom("error"), Type.bitstring(""), list]),
                Type.map(),
              ],
            ),
          );
        }

        text += String.fromCodePoint(codepoint);
      }

      return text;
    };

    // Ensures a binary is valid UTF-8; otherwise raises FunctionClauseError.
    const ensureUtf8Binary = (binary) => {
      Bitstring.maybeSetTextFromBytes(binary);

      if (binary.text === false) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(
            ":uri_string.parse_scheme_start/2",
            [binary, Type.map()],
          ),
        );
      }

      return binary.text;
    };

    const isError = (value) => Type.isTuple(value);

    const invalidUriError = (payloadChar = 58) =>
      Type.tuple([
        Type.atom("error"),
        Type.atom("invalid_uri"),
        // OTP uses charlist(":") as the invalid_uri payload; ?: = 58
        Type.list([Type.integer(payloadChar)]),
      ]);

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
      const authorityEndIndex = afterUserinfo.search(/[/?#]/);

      // Extract the authority portion (everything before /, ?, or #).
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
        return invalidUriError(payloadChar);
      }

      const hasBracketHost = afterUserinfo.startsWith("[");

      const closeBracketIndex = hasBracketHost
        ? afterUserinfo.indexOf("]")
        : -1;

      if (hasBracketHost && closeBracketIndex === -1) {
        return invalidUriError();
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
        return invalidUriError();
      }

      return {uri: {...state.uri, fragment}, remaining: ""};
    };

    // Path is always present in Erlang's uri_map result.
    const parsePathPart = (state) => {
      const pathEndMatch = state.remaining.match(/^([^?#]*)(.*)/s);
      const path = pathEndMatch[1];

      return {uri: {...state.uri, path}, remaining: pathEndMatch[2]};
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
        return invalidUriError();
      }

      if (portStr === "") {
        const newUri =
          userinfo === undefined
            ? {...uri, host, port: null}
            : {...uri, host, port: null, userinfo};

        return {uri: newUri, remaining: portRemainder};
      }

      if (!isDelimiterStart) {
        return invalidUriError();
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
