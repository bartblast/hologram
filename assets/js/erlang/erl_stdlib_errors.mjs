"use strict";

import Erlang_Maps from "../erlang/maps.mjs";
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
      bad_iterator: "not a valid iterator",
      domain_error: "is outside the domain for this function",
      not_fun_1: "not a fun that takes one argument",
      not_fun_2: "not a fun that takes two arguments",
      not_fun_3: "not a fun that takes three arguments",
      not_list: "not a list",
      not_map: "not a map",
      not_map_or_iterator: "not a map or an iterator",
      not_number: "not a number",
      not_proper_list: "not a proper list",
    };

    return texts[fragment] ?? fragment;
  },
  // End _expand_error/1
  // Deps: []

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

  // Mirrors OTP's private must_be_number/1.
  // Start _must_be_number/1
  "_must_be_number/1": (term) => (Type.isNumber(term) ? "" : "not_number"),
  // End _must_be_number/1
  // Deps: []

  // TODO: dispatch to the remaining per-module formatters from
  // :erl_stdlib_errors (format_binary_error, format_lists_error, ...) as
  // their stdlib ports migrate to bare reasons with error_info.
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

    let fragments;

    switch (frameModule.value) {
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
  // Deps: [:erl_stdlib_errors._format_error_map/3, :erl_stdlib_errors._format_maps_error/2, :erl_stdlib_errors._format_math_error/2]
};

export default Erlang_Erl_Stdlib_Errors;
