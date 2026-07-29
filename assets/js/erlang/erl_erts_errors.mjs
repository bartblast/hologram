"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Erl_Erts_Errors = {
  // Mirrors OTP's private expand_error/1, returning boxed chardata. Every
  // fragment text is colocated here. A {notEncodable: type} tag expands to
  // the two-element iolist OTP builds, and fragments without an entry
  // (e.g. "not present in map") are literal texts that pass through
  // unchanged, like OTP's expand_error(Other) -> Other fallback.
  // Start _expand_error/1
  "_expand_error/1": (fragment) => {
    if (typeof fragment === "object") {
      return Type.list([
        Type.bitstring("not a textual representation of "),
        Type.bitstring(fragment.notEncodable),
      ]);
    }

    const texts = {
      bad_base: "not an integer in the range 2 through 36",
      bad_encode_option: "not one of the atoms: latin1, utf8, or unicode",
      bad_ext_term: "invalid external representation of a term",
      bad_unicode: "invalid UTF8 encoding",
      non_existing_atom: "not an already existing atom",
      not_atom: "not an atom",
      not_binary: "not a binary",
      not_bitstring: "not a bitstring",
      not_float: "not a float",
      not_integer: "not an integer",
      not_iolist: "not an iolist term",
      not_list: "not a list",
      not_map: "not a map",
      not_number: "not a number",
      not_proper_list: "not a proper list",
      not_string: "not a list of characters",
      not_tuple: "not a tuple",
      range: "out of range",
    };

    return Type.bitstring(texts[fragment] ?? fragment);
  },
  // End _expand_error/1
  // Deps: []

  // Mirrors OTP's private format_erlang_error/3. Clauses for functions whose
  // client ports don't raise with an erl_erts_errors error_info frame are
  // omitted - they fall through to the empty fragment list, like OTP's
  // catch-all clause, so their reasons derive the plain "argument error"
  // text.
  // Start _format_erlang_error/3
  "_format_erlang_error/3": (fun, argsOrArity, _cause) => {
    const args = Type.isList(argsOrArity) ? argsOrArity.data : null;

    const mustBeBinary = (term, error = "") =>
      Type.isBinary(term) ? error : "not_binary";

    const mustBeList = (term, error = "") => {
      if (!Type.isList(term)) {
        return "not_list";
      }

      return Type.isProperList(term) ? error : "not_proper_list";
    };

    const mustBeBase = (term) =>
      Type.isInteger(term) && term.value >= 2n && term.value <= 36n
        ? ""
        : "bad_base";

    // Mirrors OTP's list_to_something/2, which probes the term with
    // length/1.
    const listToSomething = (term, error) =>
      Type.isProperList(term) ? [error] : ["not_list"];

    // Mirrors OTP's is_flat_char_list/1: a proper list of encodable
    // codepoints.
    const isFlatCharList = (term) =>
      Type.isProperList(term) &&
      term.data.every(
        (elem) =>
          Type.isInteger(elem) &&
          elem.value >= 0n &&
          elem.value <= 0x10ffffn &&
          !(elem.value >= 0xd800n && elem.value <= 0xdfffn),
      );

    // Mirrors OTP's do_binary_to_atom/3. The unicode validity probe checks
    // whether the binary decodes as UTF-8.
    const doBinaryToAtom = (bin, encoding, defaultError) => {
      const encodingName = Type.isAtom(encoding) ? encoding.value : "invalid";

      if (encodingName === "latin1") {
        return [mustBeBinary(bin, defaultError)];
      }

      if (encodingName === "unicode" || encodingName === "utf8") {
        if (!Type.isBinary(bin)) {
          return ["not_binary"];
        }

        return Bitstring.toText(bin) !== false
          ? [defaultError]
          : ["bad_unicode"];
      }

      return [mustBeBinary(bin), "bad_encode_option"];
    };

    switch (fun.value) {
      case "atom_to_binary": {
        if (args?.length === 1) {
          return ["not_atom"];
        }

        if (args?.length !== 2) {
          return [];
        }

        const [atom, encoding] = args;

        let atomError = "";

        if (!Type.isAtom(atom)) {
          atomError = "not_atom";
        } else if (Type.isAtom(encoding) && encoding.value === "latin1") {
          atomError = "contains a character not expressible in latin1";
        }

        const isKnownEncoding =
          Type.isAtom(encoding) &&
          ["latin1", "unicode", "utf8"].includes(encoding.value);

        return [
          atomError,
          isKnownEncoding ? "" : "is an invalid encoding option",
        ];
      }

      case "atom_to_list":
        return ["not_atom"];

      case "binary_to_atom": {
        if (args?.length === 1) {
          return doBinaryToAtom(args[0], Type.atom("utf8"), "");
        }

        if (args?.length !== 2) {
          return [];
        }

        return doBinaryToAtom(args[0], args[1], "");
      }

      case "binary_to_existing_atom": {
        if (args?.length === 1) {
          return doBinaryToAtom(
            args[0],
            Type.atom("utf8"),
            "non_existing_atom",
          );
        }

        if (args?.length !== 2) {
          return [];
        }

        return doBinaryToAtom(args[0], args[1], "non_existing_atom");
      }

      case "binary_to_float": {
        if (args?.length !== 1) {
          return [];
        }

        return [mustBeBinary(args[0], {notEncodable: "a float"})];
      }

      case "binary_to_integer": {
        if (args?.length === 1) {
          return [mustBeBinary(args[0], {notEncodable: "an integer"})];
        }

        if (args?.length !== 2) {
          return [];
        }

        const badBase = mustBeBase(args[1]);

        if (badBase === "") {
          return [mustBeBinary(args[0], {notEncodable: "an integer"})];
        }

        return [mustBeBinary(args[0]), badBase];
      }

      case "binary_to_list":
        return ["not_binary"];

      case "binary_to_term": {
        if (args?.length !== 1) {
          return [];
        }

        return [mustBeBinary(args[0], "bad_ext_term")];
      }

      case "bit_size":
      case "byte_size":
        return ["not_bitstring"];

      case "ceil":
      case "floor":
        return ["not_number"];

      case "element": {
        if (args?.length !== 2) {
          return [];
        }

        const [index, tuple] = args;

        let indexError = "";

        if (!Type.isInteger(index)) {
          indexError = "not_integer";
        } else if (
          index.value <= 0n ||
          (Type.isTuple(tuple) && index.value > BigInt(tuple.data.length))
        ) {
          indexError = "range";
        }

        return [indexError, Type.isTuple(tuple) ? "" : "not_tuple"];
      }

      case "float_to_binary":
      case "float_to_list": {
        if (args?.length === 1) {
          return ["not_float"];
        }

        if (args?.length !== 2) {
          return [];
        }

        const floatError = Type.isFloat(args[0]) ? "" : "not_float";
        const optionsError = mustBeList(args[1]);

        // Mirrors OTP's maybe_option_list_error/2: a well-formed options
        // list is blamed only when the float argument is fine.
        return [
          floatError,
          floatError === "" && optionsError === ""
            ? "invalid option in list"
            : optionsError,
        ];
      }

      case "integer_to_binary":
      case "integer_to_list": {
        if (args?.length === 1) {
          return ["not_integer"];
        }

        if (args?.length !== 2) {
          return [];
        }

        return [
          Type.isInteger(args[0]) ? "" : "not_integer",
          mustBeBase(args[1]),
        ];
      }

      case "is_map_key":
        return ["", "not_map"];

      case "list_to_atom": {
        if (args?.length !== 1) {
          return [];
        }

        return [mustBeList(args[0], "not_string")];
      }

      case "list_to_binary":
        return ["not_iolist"];

      case "list_to_existing_atom": {
        if (args?.length !== 1) {
          return [];
        }

        return isFlatCharList(args[0])
          ? ["non_existing_atom"]
          : [mustBeList(args[0], "not_string")];
      }

      case "list_to_float": {
        if (args?.length !== 1) {
          return [];
        }

        return listToSomething(args[0], {notEncodable: "a float"});
      }

      case "list_to_integer": {
        if (args?.length === 1) {
          return listToSomething(args[0], {notEncodable: "an integer"});
        }

        if (args?.length !== 2) {
          return [];
        }

        const badBase = mustBeBase(args[1]);

        if (badBase === "") {
          return [mustBeList(args[0], {notEncodable: "an integer"})];
        }

        return [mustBeList(args[0]), badBase];
      }

      case "list_to_pid": {
        if (args?.length !== 1) {
          return [];
        }

        return listToSomething(args[0], {notEncodable: "a pid"});
      }

      case "list_to_ref": {
        if (args?.length !== 1) {
          return [];
        }

        return listToSomething(args[0], {notEncodable: "a reference"});
      }

      case "list_to_tuple":
        return ["not_list"];

      case "length":
        return ["not_list"];

      case "map_get": {
        if (args?.length !== 2) {
          return [];
        }

        return Type.isMap(args[1]) ? ["not present in map"] : ["", "not_map"];
      }

      case "tuple_to_list":
        return ["not_tuple"];

      default:
        return [];
    }
  },
  // End _format_erlang_error/3
  // Deps: []

  // Mirrors OTP's private format_error_map/3. Fragments map to argument
  // positions in order starting at the given number, and "" entries skip
  // their position. Entries accumulate into the given boxed map.
  // Start _format_error_map/3
  "_format_error_map/3": (fragments, argumentNumber, map) => {
    const result = Type.cloneMap(map);
    let currentArgumentNumber = argumentNumber;

    for (const fragment of fragments) {
      if (fragment === "") {
        ++currentArgumentNumber;
        continue;
      }

      const expand = Erlang_Erl_Erts_Errors["_expand_error/1"];

      const key = Type.integer(currentArgumentNumber);
      result.data[Type.encodeMapKey(key)] = [key, expand(fragment)];

      ++currentArgumentNumber;
    }

    return result;
  },
  // End _format_error_map/3
  // Deps: [:erl_erts_errors._expand_error/1]

  // Start format_error/2
  "format_error/2": (reason, stacktrace) => {
    const isFourTupleTopFrame =
      Type.isList(stacktrace) &&
      stacktrace.data.length > 0 &&
      Type.isTuple(stacktrace.data[0]) &&
      stacktrace.data[0].data.length === 4;

    if (!isFourTupleTopFrame) {
      Interpreter.raiseFunctionClauseErrorMsg(
        Interpreter.buildFunctionClauseErrorMsg(
          ":erl_erts_errors.format_error/2",
          [reason, stacktrace],
        ),
      );
    }

    const frameModule = stacktrace.data[0].data[0];
    const frameFun = stacktrace.data[0].data[1];
    const frameArgsOrArity = stacktrace.data[0].data[2];
    const frameLocation = stacktrace.data[0].data[3];

    // Mirrors OTP's cause lookup: the location's error_info map may carry a
    // cause entry that refines the formatter's diagnosis, defaulting to
    // :none.
    let cause = Type.atom("none");

    if (Type.isList(frameLocation)) {
      for (const entry of frameLocation.data) {
        if (
          Type.isTuple(entry) &&
          entry.data.length === 2 &&
          Type.isAtom(entry.data[0]) &&
          entry.data[0].value === "error_info" &&
          Type.isMap(entry.data[1])
        ) {
          const causeEntry =
            entry.data[1].data[Type.encodeMapKey(Type.atom("cause"))];

          if (causeEntry !== undefined) {
            cause = causeEntry[1];
          }
        }
      }
    }

    let fragments = [];

    // Mirrors OTP's system_limit clause: the reason's explanation is clear
    // enough, so the arguments get no detailed fragments.
    const isSystemLimit =
      Type.isAtom(reason) && reason.value === "system_limit";

    if (!isSystemLimit && frameModule.value === "erlang") {
      fragments = Erlang_Erl_Erts_Errors["_format_erlang_error/3"](
        frameFun,
        frameArgsOrArity,
        cause,
      );
    }

    return Erlang_Erl_Erts_Errors["_format_error_map/3"](
      fragments,
      1,
      Type.map(),
    );
  },
  // End format_error/2
  // Deps: [:erl_erts_errors._format_erlang_error/3, :erl_erts_errors._format_error_map/3]
};

export default Erlang_Erl_Erts_Errors;
