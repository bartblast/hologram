"use strict";

import Bitstring from "../bitstring.mjs";
import Erlang_Binary from "../erlang/binary.mjs";
import Erlang_Maps from "../erlang/maps.mjs";
import Erlang_Unicode from "../erlang/unicode.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Erl_Stdlib_Errors = {
  // Mirrors OTP's private expand_error/1. Every fragment text is colocated
  // here. The formatter clauses and must_be_* helpers return tags, and fragments
  // without an entry (e.g. "not present in map") are literal chardata that
  // passes through unchanged, like OTP's expand_error(Other) -> Other
  // fallback. The not_fun tags form a closed set: the arity is always a
  // literal demanded by a formatter clause, and OTP names no arities beyond
  // these.
  // Start _expand_error/1
  "_expand_error/1": (fragment) => {
    const texts = {
      bad_binary_pattern: "not a valid pattern",
      bad_char_data: "not valid character data (an iodata term)",
      bad_encoding: "not a valid encoding",
      bad_iterator: "not a valid iterator",
      bad_options: "invalid options",
      bad_replacement: "not a valid replacement",
      bitstring: "is a bitstring (expected a binary)",
      domain_error: "is outside the domain for this function",
      empty_binary: "a zero-sized binary is not allowed",
      not_binary: "not a binary",
      not_fun_1: "not a fun that takes one argument",
      not_fun_2: "not a fun that takes two arguments",
      not_fun_3: "not a fun that takes three arguments",
      not_integer: "not an integer",
      not_list: "not a list",
      not_map: "not a map",
      not_map_or_iterator: "not a map or an iterator",
      not_number: "not a number",
      not_proper_list: "not a proper list",
      range: "out of range",
    };

    return texts[fragment] ?? fragment;
  },
  // End _expand_error/1
  // Deps: []

  // Mirrors OTP's private format_binary_error/3. The cause is the boxed
  // atom from the frame's error_info map (:none when absent) - only the
  // replace/4 clause consults it. The matches clauses delegate to the match
  // clauses, like OTP's do. Clauses for functions with no client port
  // (bin_to_list, decode_hex, decode_unsigned, encode_hex, encode_unsigned,
  // join, list_to_bin, longest_common_prefix, longest_common_suffix, part,
  // referenced_byte_size, unhex) are omitted - like any unknown function,
  // they fall through to the function clause error, which on the server
  // only unknown functions reach.
  // Start _format_binary_error/3
  "_format_binary_error/3": (fun, argsOrArity, cause) => {
    const mustBeBinary = Erlang_Erl_Stdlib_Errors["_must_be_binary/1"];
    const mustBePattern = Erlang_Erl_Stdlib_Errors["_must_be_pattern/1"];
    const mustBePosition = Erlang_Erl_Stdlib_Errors["_must_be_position/1"];

    const mustBeNonNegInteger =
      Erlang_Erl_Stdlib_Errors["_must_be_non_neg_integer/1"];

    const mustBeReplacement =
      Erlang_Erl_Stdlib_Errors["_must_be_binary_replacement/1"];

    const args = Type.isList(argsOrArity) ? argsOrArity.data : null;

    if (fun.value === "matches") {
      return Erlang_Erl_Stdlib_Errors["_format_binary_error/3"](
        Type.atom("match"),
        argsOrArity,
        cause,
      );
    }

    // Mirrors OTP's clause head [{scope, {Start, Len}}] with integer
    // Start and Len, which turns a syntactically valid scope option into
    // the part-not-inside-binary diagnosis.
    const isSingleScopeOption = (options) => {
      if (!Type.isList(options) || options.data.length !== 1) {
        return false;
      }

      const option = options.data[0];

      if (
        !Type.isTuple(option) ||
        option.data.length !== 2 ||
        !Type.isAtom(option.data[0]) ||
        option.data[0].value !== "scope"
      ) {
        return false;
      }

      const scope = option.data[1];

      return (
        Type.isTuple(scope) &&
        scope.data.length === 2 &&
        Type.isInteger(scope.data[0]) &&
        Type.isInteger(scope.data[1])
      );
    };

    const isEmptyBinary = (term) => {
      if (!Type.isBinary(term)) {
        return false;
      }

      Bitstring.maybeSetBytesFromText(term);

      return term.bytes.length === 0;
    };

    switch (fun.value) {
      case "at":
        if (args?.length === 2) {
          return [mustBeBinary(args[0]), mustBePosition(args[1])];
        }
        break;

      case "compile_pattern":
        if (args?.length === 1) {
          return ["not a valid pattern"];
        }
        break;

      case "copy":
        if (args?.length === 1) {
          return [mustBeBinary(args[0])];
        }

        if (args?.length === 2) {
          return [mustBeBinary(args[0]), mustBeNonNegInteger(args[1])];
        }
        break;

      case "first":
      case "last":
        if (args?.length === 1) {
          return [
            isEmptyBinary(args[0]) ? "empty_binary" : mustBeBinary(args[0]),
          ];
        }
        break;

      case "match":
        if (args?.length === 2) {
          return [mustBeBinary(args[0]), mustBePattern(args[1])];
        }

        if (args?.length === 3) {
          const errors = [mustBeBinary(args[0]), mustBePattern(args[1])];

          if (errors[0] !== "" || errors[1] !== "") {
            return errors;
          }

          return [
            "",
            "",
            isSingleScopeOption(args[2])
              ? "specified part is not wholly inside binary"
              : "bad_options",
          ];
        }
        break;

      case "replace":
        if (args?.length === 3) {
          return [
            mustBeBinary(args[0]),
            mustBePattern(args[1]),
            mustBeReplacement(args[2]),
          ];
        }

        if (args?.length === 4) {
          const errors = [
            mustBeBinary(args[0]),
            mustBePattern(args[1]),
            mustBeReplacement(args[2]),
          ];

          if (cause.value === "badopt") {
            return [...errors, "bad_options"];
          }

          // Options are syntactically correct, but not semantically
          // (e.g. referencing outside the subject).
          if (errors.every((error) => error === "")) {
            return ["", "", "", "bad_options"];
          }

          return errors;
        }
        break;

      case "split":
        if (args?.length === 2) {
          return [mustBeBinary(args[0]), mustBePattern(args[1])];
        }

        if (args?.length === 3) {
          const errors = [mustBeBinary(args[0]), mustBePattern(args[1])];

          if (errors[0] !== "" || errors[1] !== "") {
            return errors;
          }

          return ["", "", "bad_options"];
        }
        break;
    }

    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(
        ":erl_stdlib_errors.format_binary_error/3",
        [fun, argsOrArity, cause],
      ),
    );
  },
  // End _format_binary_error/3
  // Deps: [:erl_stdlib_errors._must_be_binary/1, :erl_stdlib_errors._must_be_binary_replacement/1, :erl_stdlib_errors._must_be_non_neg_integer/1, :erl_stdlib_errors._must_be_pattern/1, :erl_stdlib_errors._must_be_position/1]

  // Mirrors OTP's private format_error_map/3. Fragments map to argument
  // positions in order starting at the given number, "" entries skip their
  // position, and {general: text} entries land under the :general key
  // instead of consuming a position. Entries accumulate into the given
  // boxed map.
  // Start _format_error_map/3
  "_format_error_map/3": (fragments, argumentNumber, map) => {
    const result = Type.cloneMap(map);
    let currentArgumentNumber = argumentNumber;

    for (const fragment of fragments) {
      if (fragment === "") {
        ++currentArgumentNumber;
        continue;
      }

      const expand = Erlang_Erl_Stdlib_Errors["_expand_error/1"];

      if (typeof fragment === "object") {
        const key = Type.atom("general");
        result.data[Type.encodeMapKey(key)] = [
          key,
          Type.bitstring(expand(fragment.general)),
        ];

        continue;
      }

      const key = Type.integer(currentArgumentNumber);
      result.data[Type.encodeMapKey(key)] = [
        key,
        Type.bitstring(expand(fragment)),
      ];

      ++currentArgumentNumber;
    }

    return result;
  },
  // End _format_error_map/3
  // Deps: [:erl_stdlib_errors._expand_error/1]

  // Mirrors OTP's private format_maps_error/2 as a spec table, one entry
  // per OTP clause. An array spec lists per-argument fragments: a validator
  // function is applied to the argument at its position, a constant is emitted as
  // given ("" skips the position). A function spec (get, update) carries the
  // clause's own conditional logic. Specs for maps functions that have no
  // client port (filter, filtermap, foreach, groups_from_list, iterator/2,
  // size, update_with, with, without) are omitted - like any unknown
  // function, they fall through to the function clause error, which on the
  // server only unknown functions reach.
  // Start _format_maps_error/2
  "_format_maps_error/2": (fun, argsOrArity) => {
    const raiseFunctionClause = () => {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(
          ":erl_stdlib_errors.format_maps_error/2",
          [fun, argsOrArity],
        ),
      );
    };

    const mustBeFun = (arity) => (term) =>
      Erlang_Erl_Stdlib_Errors["_must_be_fun/2"](term, arity);

    const mustBeList = Erlang_Erl_Stdlib_Errors["_must_be_list/1"];
    const mustBeMap = Erlang_Erl_Stdlib_Errors["_must_be_map/1"];
    const mustBeMapOrIter = Erlang_Erl_Stdlib_Errors["_must_be_map_or_iter/1"];

    const specs = {
      find: ["", "not_map"],
      fold: [mustBeFun(3), "", mustBeMapOrIter],
      from_keys: [mustBeList, ""],
      from_list: [mustBeList],
      get: (args) => {
        if (args?.length === 2) {
          return Type.isMap(args[1]) ? ["not present in map"] : ["", "not_map"];
        }

        if (args?.length === 3) {
          return ["", "not_map"];
        }

        raiseFunctionClause();
      },
      intersect: [mustBeMap, mustBeMap],
      intersect_with: [mustBeFun(3), mustBeMap, mustBeMap],
      is_key: ["", "not_map"],
      iterator: [mustBeMap],
      keys: ["not_map"],
      map: [mustBeFun(2), mustBeMapOrIter],
      merge: [mustBeMap, mustBeMap],
      merge_with: [mustBeFun(3), mustBeMap, mustBeMap],
      next: ["bad_iterator"],
      put: ["", "", "not_map"],
      remove: ["", "not_map"],
      take: ["", "not_map"],
      to_list: ["not_map_or_iterator"],
      update: (args) =>
        args?.length === 3 && Type.isMap(args[2])
          ? ["not present in map", "", ""]
          : ["", "", "not_map"],
      values: ["not_map"],
    };

    const args = Type.isList(argsOrArity) ? argsOrArity.data : null;
    const spec = specs[fun.value];

    if (spec === undefined) {
      raiseFunctionClause();
    }

    if (typeof spec === "function") {
      return spec(args);
    }

    // A spec with validators destructures the args like the OTP clause head
    // does - an arity or a wrong-length args list matches no clause.
    const hasValidators = spec.some((entry) => typeof entry === "function");

    if (hasValidators && args?.length !== spec.length) {
      raiseFunctionClause();
    }

    return spec.map((entry, index) =>
      typeof entry === "function" ? entry(args[index]) : entry,
    );
  },
  // End _format_maps_error/2
  // Deps: [:erl_stdlib_errors._must_be_fun/2, :erl_stdlib_errors._must_be_list/1, :erl_stdlib_errors._must_be_map/1, :erl_stdlib_errors._must_be_map_or_iter/1]

  // Mirrors OTP's private format_math_error/2 and its maybe_domain_error/1
  // helper. The domain-error set lists the functions whose clauses report a
  // number outside the function's domain; every other math function falls to
  // the catch-all clauses keyed by argument count, so unknown functions never
  // reach a function clause error here. The fmod spec is omitted - the
  // function has no client port, so only its zero-divisor case would diverge
  // from the catch-all.
  // Start _format_math_error/2
  "_format_math_error/2": (fun, argsOrArity) => {
    const mustBeNumber = Erlang_Erl_Stdlib_Errors["_must_be_number/1"];

    const args = Type.isList(argsOrArity) ? argsOrArity.data : null;

    const domainErrorFuns = [
      "acos",
      "acosh",
      "asin",
      "atanh",
      "log",
      "log2",
      "log10",
      "sqrt",
    ];

    if (domainErrorFuns.includes(fun.value)) {
      if (args?.length !== 1) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(
            ":erl_stdlib_errors.maybe_domain_error/1",
            [argsOrArity],
          ),
        );
      }

      const fragment = mustBeNumber(args[0]);

      return [fragment === "" ? "domain_error" : fragment];
    }

    if (args?.length === 1) {
      return [mustBeNumber(args[0])];
    }

    if (args?.length === 2) {
      return [mustBeNumber(args[0]), mustBeNumber(args[1])];
    }

    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(
        ":erl_stdlib_errors.format_math_error/2",
        [fun, argsOrArity],
      ),
    );
  },
  // End _format_math_error/2
  // Deps: [:erl_stdlib_errors._must_be_number/1]

  // Mirrors OTP's private format_unicode_error/2. The characters_to_list
  // clause delegates to the characters_to_binary clauses, like OTP's does.
  // Clauses for functions with no client port (category, is_whitespace,
  // is_id_start, is_id_continue) are omitted - like any unknown function,
  // they fall through to the function clause error, which on the server
  // only unknown functions reach.
  // Start _format_unicode_error/2
  "_format_unicode_error/2": (fun, argsOrArity) => {
    const unicodeCharData = Erlang_Erl_Stdlib_Errors["_unicode_char_data/1"];
    const unicodeEncoding = Erlang_Erl_Stdlib_Errors["_unicode_encoding/1"];

    const badCharDataFuns = [
      "characters_to_nfc_binary",
      "characters_to_nfc_list",
      "characters_to_nfd_binary",
      "characters_to_nfd_list",
      "characters_to_nfkc_binary",
      "characters_to_nfkc_list",
      "characters_to_nfkd_binary",
      "characters_to_nfkd_list",
    ];

    const args = Type.isList(argsOrArity) ? argsOrArity.data : null;

    if (fun.value === "characters_to_list") {
      return Erlang_Erl_Stdlib_Errors["_format_unicode_error/2"](
        Type.atom("characters_to_binary"),
        argsOrArity,
      );
    }

    if (fun.value === "characters_to_binary") {
      if (args?.length === 1) {
        return ["bad_char_data"];
      }

      if (args?.length === 2) {
        return [unicodeCharData(args[0]), unicodeEncoding(args[1])];
      }

      if (args?.length === 3) {
        return [
          unicodeCharData(args[0]),
          unicodeEncoding(args[1]),
          unicodeEncoding(args[2]),
        ];
      }
    }

    if (badCharDataFuns.includes(fun.value) && args?.length === 1) {
      return ["bad_char_data"];
    }

    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(
        ":erl_stdlib_errors.format_unicode_error/2",
        [fun, argsOrArity],
      ),
    );
  },
  // End _format_unicode_error/2
  // Deps: [:erl_stdlib_errors._unicode_char_data/1, :erl_stdlib_errors._unicode_encoding/1]

  // Mirrors OTP's private must_be_binary/1.
  // Start _must_be_binary/1
  "_must_be_binary/1": (term) => {
    if (Type.isBinary(term)) {
      return "";
    }

    return Type.isBitstring(term) ? "bitstring" : "not_binary";
  },
  // End _must_be_binary/1
  // Deps: []

  // Mirrors OTP's private must_be_binary_replacement/1.
  // Start _must_be_binary_replacement/1
  "_must_be_binary_replacement/1": (term) => {
    if (Type.isBinary(term)) {
      return "";
    }

    return Type.isAnonymousFunction(term) && term.arity === 1
      ? ""
      : "bad_replacement";
  },
  // End _must_be_binary_replacement/1
  // Deps: []

  // Mirrors OTP's private must_be_fun/2.
  // Start _must_be_fun/2
  "_must_be_fun/2": (term, arity) =>
    Type.isAnonymousFunction(term) && term.arity === arity
      ? ""
      : `not_fun_${arity}`,
  // End _must_be_fun/2
  // Deps: []

  // Mirrors OTP's private must_be_list/1.
  // Start _must_be_list/1
  "_must_be_list/1": (term) => {
    if (!Type.isList(term)) {
      return "not_list";
    }

    return Type.isProperList(term) ? "" : "not_proper_list";
  },
  // End _must_be_list/1
  // Deps: []

  // Mirrors OTP's private must_be_map/1.
  // Start _must_be_map/1
  "_must_be_map/1": (term) => (Type.isMap(term) ? "" : "not_map"),
  // End _must_be_map/1
  // Deps: []

  // Mirrors OTP's private must_be_map_or_iter/1.
  // Start _must_be_map_or_iter/1
  "_must_be_map_or_iter/1": (term) =>
    Type.isMap(term) || Type.isTrue(Erlang_Maps["is_iterator_valid/1"](term))
      ? ""
      : "not_map_or_iterator",
  // End _must_be_map_or_iter/1
  // Deps: [:maps.is_iterator_valid/1]

  // Mirrors OTP's private must_be_non_neg_integer/1, which resolves to
  // must_be_integer/3 with a range of 0 to infinity.
  // Start _must_be_non_neg_integer/1
  "_must_be_non_neg_integer/1": (term) => {
    if (!Type.isInteger(term)) {
      return "not_integer";
    }

    return term.value >= 0n ? "" : "range";
  },
  // End _must_be_non_neg_integer/1
  // Deps: []

  // Mirrors OTP's private must_be_number/1.
  // Start _must_be_number/1
  "_must_be_number/1": (term) => (Type.isNumber(term) ? "" : "not_number"),
  // End _must_be_number/1
  // Deps: []

  // Mirrors OTP's private must_be_pattern/1, which probes the term by
  // attempting a binary:match/2 call with it and treats a badarg raise as
  // an invalid pattern. The non-raising validity check is used instead of
  // the raising port - this runs inside message derivation, so a raise here
  // would derive its own message and recurse.
  // Start _must_be_pattern/1
  "_must_be_pattern/1": (term) =>
    Erlang_Binary["_is_valid_pattern/1"](term) ? "" : "bad_binary_pattern",
  // End _must_be_pattern/1
  // Deps: [:binary._is_valid_pattern/1]

  // Mirrors OTP's private must_be_position/1.
  // Start _must_be_position/1
  "_must_be_position/1": (term) => {
    if (!Type.isInteger(term)) {
      return "not_integer";
    }

    return term.value >= 0n ? "" : "range";
  },
  // End _must_be_position/1
  // Deps: []

  // Mirrors OTP's private unicode_char_data/1, which probes the term by
  // attempting a characters_to_binary conversion and treats an error or
  // incomplete result (or a raise) as bad chardata. The non-raising
  // conversion core is used instead of the raising port - this runs inside
  // message derivation, so a raise here would derive its own message and
  // recurse.
  // Start _unicode_char_data/1
  "_unicode_char_data/1": (chars) => {
    const result = Erlang_Unicode["_chardata_to_utf8_binary/1"](chars);

    return result === null || Type.isTuple(result) ? "bad_char_data" : "";
  },
  // End _unicode_char_data/1
  // Deps: [:unicode._chardata_to_utf8_binary/1]

  // Mirrors OTP's private unicode_encoding/1, which probes the term by
  // attempting a conversion with it as the encoding. The client checks
  // membership in the encoding set that OTP's characters_to_binary/2
  // accepts instead: latin1, unicode, utf8, utf16, utf32, and the
  // {utf16 | utf32, big | little} tuples.
  // Start _unicode_encoding/1
  "_unicode_encoding/1": (encoding) => {
    if (
      Type.isAtom(encoding) &&
      ["latin1", "unicode", "utf8", "utf16", "utf32"].includes(encoding.value)
    ) {
      return "";
    }

    const isEndiannessTuple =
      Type.isTuple(encoding) &&
      encoding.data.length === 2 &&
      Type.isAtom(encoding.data[0]) &&
      ["utf16", "utf32"].includes(encoding.data[0].value) &&
      Type.isAtom(encoding.data[1]) &&
      ["big", "little"].includes(encoding.data[1].value);

    return isEndiannessTuple ? "" : "bad_encoding";
  },
  // End _unicode_encoding/1
  // Deps: []

  // TODO: dispatch to the remaining per-module formatters from
  // :erl_stdlib_errors (format_lists_error, ...) as their stdlib ports
  // migrate to bare reasons with error_info.
  // Start format_error/2
  "format_error/2": (reason, stacktrace) => {
    const isFourTupleTopFrame =
      Type.isList(stacktrace) &&
      stacktrace.data.length > 0 &&
      Type.isTuple(stacktrace.data[0]) &&
      stacktrace.data[0].data.length === 4;

    if (!isFourTupleTopFrame) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(
          ":erl_stdlib_errors.format_error/2",
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

    let fragments;

    switch (frameModule.value) {
      case "binary":
        fragments = Erlang_Erl_Stdlib_Errors["_format_binary_error/3"](
          frameFun,
          frameArgsOrArity,
          cause,
        );
        break;

      case "maps":
        fragments = Erlang_Erl_Stdlib_Errors["_format_maps_error/2"](
          frameFun,
          frameArgsOrArity,
        );
        break;

      case "math":
        fragments = Erlang_Erl_Stdlib_Errors["_format_math_error/2"](
          frameFun,
          frameArgsOrArity,
        );
        break;

      case "unicode":
        fragments = Erlang_Erl_Stdlib_Errors["_format_unicode_error/2"](
          frameFun,
          frameArgsOrArity,
        );
        break;

      default:
        fragments = [];
    }

    return Erlang_Erl_Stdlib_Errors["_format_error_map/3"](
      fragments,
      1,
      Type.map(),
    );
  },
  // End format_error/2
  // Deps: [:erl_stdlib_errors._format_binary_error/3, :erl_stdlib_errors._format_error_map/3, :erl_stdlib_errors._format_maps_error/2, :erl_stdlib_errors._format_math_error/2, :erl_stdlib_errors._format_unicode_error/2]
};

export default Erlang_Erl_Stdlib_Errors;
