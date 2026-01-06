"use strict";

import Erlang_Lists from "./lists.mjs";
import Erlang_Maps from "./maps.mjs";
import HologramInterpreterError from "../errors/interpreter_error.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Sets = {
  // Start _validate_opts/1
  "_validate_opts/1": (opts) => {
    if (!Type.isList(opts)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":proplists.get_value/3", [
          Type.atom("version"),
          opts,
          Type.integer(1),
        ]),
      );
    }

    if (Type.isImproperList(opts)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":proplists.get_value/3"),
      );
    }

    const versionOptTuple = Erlang_Lists["keyfind/3"](
      Type.atom("version"),
      Type.integer(1),
      opts,
    );

    if (Type.isFalse(versionOptTuple)) {
      throw new HologramInterpreterError(
        "Hologram requires to specify :sets version explicitely",
      );
    }

    const version = versionOptTuple.data[1];

    if (Type.isInteger(version)) {
      if (version.value === 2n) return;

      if (version.value === 1n) {
        throw new HologramInterpreterError(
          "Hologram doesn't support :sets version 1",
        );
      }
    }

    Interpreter.raiseCaseClauseError(version);
  },
  // End _validate_opts/1
  // Deps: [:lists.keyfind/3]

  // Start from_list/2
  "from_list/2": (list, opts) => {
    Erlang_Sets["_validate_opts/1"](opts);
    return Erlang_Maps["from_keys/2"](list, Type.list());
  },
  // End from_list/2
  // Deps: [:maps.from_keys/2, :sets._validate_opts/1]

  // Start is_element/2
  "is_element/2": (element, set) => {
    if (!Type.isMap(set)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":sets.is_element/2", [
          element,
          set,
        ]),
      );
    }

    return Erlang_Maps["is_key/2"](element, set);
  },
  // End is_element/2
  // Deps: [:maps.is_key/2]

  // Start new/1
  "new/1": (opts) => {
    Erlang_Sets["_validate_opts/1"](opts);
    return Type.map();
  },
  // End new/1
  // Deps: [:sets._validate_opts/1]

  // Start fold/3
  "fold/3": (fun, initialAcc, set) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2 || !Type.isMap(set)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":sets.fold/3", [
          fun,
          initialAcc,
          set,
        ]),
      );
    }

    const elements = Erlang_Maps["keys/1"](set);
    return elements.data.reduce((acc, elem) => {
      return Interpreter.callAnonymousFunction(fun, [elem, acc]);
    }, initialAcc);
  },
  // End fold/3
  // Deps: [:maps.keys/1]

  // Start to_list/1
  "to_list/1": (set) => {
    if (!Type.isMap(set)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":sets.to_list/1", [set]),
      );
    }

    return Erlang_Maps["keys/1"](set);
  },
  // End to_list/1
  // Deps: [:maps.keys/1]
};

export default Erlang_Sets;
