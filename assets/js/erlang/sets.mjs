"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";
import Erlang_Maps from "./maps.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// :sets v2 functions work with maps internally
// The set is represented as a map where keys are the elements and values are empty lists []

const Erlang_Sets = {
  // Start new/0
  "new/0": () => {
    // Return a map (version 2 representation)
    return Type.map([]);
  },
  // End new/0
  // Deps: []

  // Start new/1
  "new/1": (opts) => {
    if (!Type.isList(opts)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":sets.new/1", [opts]),
      );
    }

    return Type.map([]);
  },
  // End new/1
  // Deps: []

  // Start from_list/2
  "from_list/2": (list, opts) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":sets.from_list/2", [
          list,
          opts,
        ]),
      );
    }

    if (!Type.isList(opts)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":sets.from_list/2", [
          list,
          opts,
        ]),
      );
    }

    let set = Type.map([]);
    const emptyList = Type.list([]);

    for (const element of list.data) {
      if (!Type.isTrue(Erlang_Maps["is_key/2"](element, set))) {
        set = Erlang_Maps["put/3"](element, emptyList, set);
      }
    }

    return set;
  },
  // End from_list/2
  // Deps: [:maps.is_key/2, :maps.put/3]

  // Start add_element/2
  "add_element/2": (element, set) => {
    if (!Type.isMap(set)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":sets.add_element/2", [
          element,
          set,
        ]),
      );
    }
    if (Type.isTrue(Erlang_Maps["is_key/2"](element, set))) {
      return set;
    }

    return Erlang_Maps["put/3"](element, Type.list([]), set);
  },
  // End add_element/2
  // Deps: [:maps.is_key/2, :maps.put/3]

  // Start del_element/2
  "del_element/2": (element, set) => {
    if (!Type.isMap(set)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":sets.del_element/2", [
          element,
          set,
        ]),
      );
    }

    return Erlang_Maps["remove/2"](element, set);
  },
  // End del_element/2
  // Deps: [:maps.remove/2]

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
};

export default Erlang_Sets;
