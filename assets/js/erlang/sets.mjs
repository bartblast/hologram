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

    return Erlang_Maps["put/3"](element, Type.list(), set);
  },
  // End add_element/2
  // Deps: [:maps.put/3]

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

  // Start is_disjoint/2
  "is_disjoint/2": (set1, set2) => {
    [set1, set2].forEach((set) => {
      if (!Type.isMap(set)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":sets.is_disjoint/2", [
            set1,
            set2,
          ]),
        );
      }
    });

    const encodedKeys1 = new Set(Object.keys(set1.data));
    const encodedKeys2 = new Set(Object.keys(set2.data));
    return Type.boolean(encodedKeys1.isDisjointFrom(encodedKeys2));
  },
  // End is_disjoint/2
  // Deps: []

  // Start filter/2
  "filter/2": (fun, set) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1 || !Type.isMap(set)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":sets.filter/2", [fun, set]),
      );
    }

    const predicate = ([key, _value]) => {
      const result = Interpreter.callAnonymousFunction(fun, [key]);

      if (!Type.isBoolean(result)) {
        Interpreter.raiseErlangError(
          Interpreter.buildErlangErrorMsg(
            `{:bad_filter, ${Interpreter.inspect(result)}}`,
          ),
        );
      }

      return Type.isTrue(result);
    };

    return Type.map(Object.values(set.data).filter(predicate));
  },
  // End filter/2
  // Deps: []

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

  // Start is_subset/2
  "is_subset/2": (set1, set2) => {
    if (!Type.isMap(set1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":sets.fold/3"),
      );
    }

    if (Object.keys(set1.data).length === 0) {
      return Type.boolean(true);
    }

    const set1Items = Erlang_Sets["to_list/1"](set1).data;

    if (!Type.isMap(set2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":sets.is_element/2", [
          set1Items[0],
          set2,
        ]),
      );
    }

    return Type.boolean(
      set1Items.every((item) =>
        Type.isTrue(Erlang_Sets["is_element/2"](item, set2)),
      ),
    );
  },
  // End is_subset/2
  // Deps: [:sets.is_element/2, :sets.to_list/1]

  // Start new/1
  "new/1": (opts) => {
    Erlang_Sets["_validate_opts/1"](opts);
    return Type.map();
  },
  // End new/1
  // Deps: [:sets._validate_opts/1]

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
