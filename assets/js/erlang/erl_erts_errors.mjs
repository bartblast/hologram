"use strict";

import Bitstring from "../bitstring.mjs";
import ERTS from "../erts.mjs";
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
      bad_time_unit: "invalid time unit",
      bad_encode_option: "not one of the atoms: latin1, utf8, or unicode",
      bad_ext_term: "invalid external representation of a term",
      bad_unicode: "invalid UTF8 encoding",
      non_existing_atom: "not an already existing atom",
      not_atom: "not an atom",
      not_binary: "not a binary",
      not_bitstring: "not a bitstring",
      not_cons: "not a nonempty list",
      not_float: "not a float",
      not_fun: "not a fun",
      not_integer: "not an integer",
      not_iodata: "not an iodata term",
      not_iolist: "not an iolist term",
      not_list: "not a list",
      not_map: "not a map",
      not_number: "not a number",
      not_pid: "not a pid",
      not_proper_list: "not a proper list",
      not_ref: "not a reference",
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

    const mustBeAtom = (term) => (Type.isAtom(term) ? "" : "not_atom");

    const mustBeInt = (term) => (Type.isInteger(term) ? "" : "not_integer");

    const mustBeNonNegInt = (term) => {
      if (!Type.isInteger(term)) {
        return "not_integer";
      }

      return term.value >= 0n ? "" : "range";
    };

    // Mirrors OTP's must_be_time_unit/1, which probes the term with a
    // convert_time_unit call - the client uses the non-raising validity
    // check instead.
    const mustBeTimeUnit = (term) =>
      Erlang["_is_valid_time_unit/1"](term) ? "" : "bad_time_unit";

    // Mirrors OTP's element clause, shared by the delete_element,
    // insert_element, and setelement delegations.
    const elementFragments = (index, tuple) => {
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
    };

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
      case "abs":
      case "float":
      case "round":
      case "trunc":
        return ["not_number"];

      case "append_element":
        return ["not_tuple"];

      case "apply": {
        if (args?.length !== 3) {
          return [];
        }

        return [mustBeAtom(args[0]), mustBeAtom(args[1]), mustBeList(args[2])];
      }

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

      case "binary_part": {
        if (args?.length !== 3) {
          return [];
        }

        const [bin, pos, len] = args;

        const errors = [
          mustBeBinary(bin),
          mustBeNonNegInt(pos),
          mustBeInt(len),
        ];

        if (errors.some((error) => error !== "")) {
          return errors;
        }

        Bitstring.maybeSetBytesFromText(bin);

        if (pos.value > BigInt(bin.bytes.length)) {
          return ["", "range"];
        }

        return ["", "", "range"];
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

      case "convert_time_unit": {
        if (args?.length !== 3) {
          return [];
        }

        return [
          mustBeInt(args[0]),
          mustBeTimeUnit(args[1]),
          mustBeTimeUnit(args[2]),
        ];
      }

      case "delete_element":
      case "element": {
        if (args?.length !== 2) {
          return [];
        }

        return elementFragments(args[0], args[1]);
      }

      case "fun_info": {
        if (args?.length === 1) {
          return ["not_fun"];
        }

        if (args?.length !== 2) {
          return [];
        }

        return Type.isAnonymousFunction(args[0])
          ? ["", "invalid item"]
          : ["not_fun"];
      }

      case "function_exported":
      case "make_fun": {
        if (args?.length !== 3) {
          return [];
        }

        return [
          mustBeAtom(args[0]),
          mustBeAtom(args[1]),
          mustBeNonNegInt(args[2]),
        ];
      }

      case "hd":
      case "tl":
        return ["not_cons"];

      case "insert_element":
      case "setelement": {
        if (args?.length !== 3) {
          return [];
        }

        return elementFragments(args[0], args[1]);
      }

      case "iolist_to_binary":
        return ["not_iodata"];

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

      case "make_tuple": {
        if (args?.length !== 2) {
          return [];
        }

        return ["range"];
      }

      case "monotonic_time":
      case "system_time":
      case "time_offset":
        return ["bad_time_unit"];

      case "pid_to_list":
        return ["not_pid"];

      case "ref_to_list":
        return ["not_ref"];

      case "split_binary": {
        if (args?.length !== 2) {
          return [];
        }

        const [bin, pos] = args;
        const errors = [mustBeBinary(bin), mustBeNonNegInt(pos)];

        if (errors.some((error) => error !== "")) {
          return errors;
        }

        Bitstring.maybeSetBytesFromText(bin);

        return pos.value > BigInt(bin.bytes.length) ? ["", "range"] : [];
      }

      case "system_info":
        return ["invalid system info item"];

      case "unique_integer": {
        if (args?.length !== 1) {
          return [];
        }

        return [mustBeList(args[0], "invalid modifier")];
      }

      case "length":
        return ["not_list"];

      case "map_get": {
        if (args?.length !== 2) {
          return [];
        }

        return Type.isMap(args[1]) ? ["not present in map"] : ["", "not_map"];
      }

      case "tuple_size":
      case "tuple_to_list":
        return ["not_tuple"];

      default:
        return [];
    }
  },
  // End _format_erlang_error/3
  // Deps: [:erlang._is_valid_time_unit/1]

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

  // Mirrors OTP's format_bs_fail/2 with its do_format_bs_fail helpers. The
  // frame's error_info pretty printer is applied to the offending value;
  // when absent, the client substitutes Elixir-style inspection for OTP's
  // possibly_truncated default - the client derivation path (Exception's
  // error_info handling) always injects Elixir's &inspect/1 anyway. The
  // cause shapes form a closed set produced by the BEAM's binary
  // construction instructions, so there is no function clause fallback for
  // unknown error tags.
  // Start format_bs_fail/2
  "format_bs_fail/2": (reason, stacktrace) => {
    const frame = ERTS.callStack.unboxTopFrame(stacktrace);

    if (frame === null) {
      Interpreter.raiseFunctionClauseError(
        "erl_erts_errors",
        "format_bs_fail",
        2,
        [reason, stacktrace],
      );
    }

    const errorInfoMap = frame.errorInfo;

    const cause =
      errorInfoMap?.data[Type.encodeMapKey(Type.atom("cause"))]?.[1];

    if (
      cause === undefined ||
      !Type.isTuple(cause) ||
      cause.data.length !== 4
    ) {
      return Type.map();
    }

    const [segment, type, errorTag, value] = cause.data;

    const overrideEntry =
      errorInfoMap.data[
        Type.encodeMapKey(Type.atom("override_segment_position"))
      ];

    const segmentPosition = overrideEntry ? overrideEntry[1] : segment;

    const prettyPrinterEntry =
      errorInfoMap.data[Type.encodeMapKey(Type.atom("pretty_printer"))];

    const prettyPrint = (term) => {
      if (prettyPrinterEntry === undefined) {
        return Interpreter.inspect(term);
      }

      return Bitstring.toText(
        Interpreter.callAnonymousFunction(prettyPrinterEntry[1], [term]),
      );
    };

    const formatDetail = () => {
      const typeName = type.value;
      const tag = errorTag.value;

      if (Type.isAtom(reason) && reason.value === "system_limit") {
        if (
          typeName === "binary" &&
          tag === "binary" &&
          Type.isAtom(value) &&
          value.value === "size"
        ) {
          return "the size of the binary/bitstring is too large (exceeding 2147483647 bits)";
        }

        return `the size ${Interpreter.inspect(value)} is too large`;
      }

      if (typeName === "float" && tag === "invalid") {
        return `expected one of the supported sizes 16, 32, or 64 but got: ${Interpreter.inspect(value)}`;
      }

      if (typeName === "float" && tag === "no_float") {
        return `the value ${prettyPrint(value)} is outside the range expressible as a float`;
      }

      if (typeName === "binary" && tag === "unit") {
        return `the size of the value ${prettyPrint(value)} is not a multiple of the unit for the segment`;
      }

      if (tag === "short") {
        return `the value ${prettyPrint(value)} is shorter than the size of the segment`;
      }

      if (tag === "size") {
        return `expected a non-negative integer as size but got: ${prettyPrint(value)}`;
      }

      const expected =
        {
          binary: "a binary",
          float: "a float or an integer",
          integer: "an integer",
        }[typeName] ?? `a non-negative integer encodable as ${typeName}`;

      return `expected ${expected} but got: ${prettyPrint(value)}`;
    };

    const general = `segment ${segmentPosition.value} of type '${type.value}': ${formatDetail()}`;

    return Type.map([
      [Type.atom("general"), Type.bitstring(general)],
      [Type.atom("reason"), Type.bitstring("construction of binary failed")],
    ]);
  },
  // End format_bs_fail/2
  // Deps: []

  // Start format_error/2
  "format_error/2": (reason, stacktrace) => {
    const frame = ERTS.callStack.unboxTopFrame(stacktrace);

    if (frame === null) {
      Interpreter.raiseFunctionClauseError(
        "erl_erts_errors",
        "format_error",
        2,
        [reason, stacktrace],
      );
    }

    // Mirrors OTP's cause lookup: the frame's error_info map may carry a
    // cause entry that refines the formatter's diagnosis, defaulting to
    // :none.
    const causeEntry =
      frame.errorInfo?.data[Type.encodeMapKey(Type.atom("cause"))];

    const cause = causeEntry ? causeEntry[1] : Type.atom("none");

    let fragments = [];

    // Mirrors OTP's system_limit clause: the reason's explanation is clear
    // enough, so the arguments get no detailed fragments.
    const isSystemLimit =
      Type.isAtom(reason) && reason.value === "system_limit";

    if (!isSystemLimit && frame.module.value === "erlang") {
      fragments = Erlang_Erl_Erts_Errors["_format_erlang_error/3"](
        frame.function,
        frame.arityOrArgs,
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
