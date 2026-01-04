"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Lists = {
  // Start any/2
  "any/2": (fun, list) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.any/2", []),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseCaseClauseError(list);
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.any/2", [list]),
      );
    }

    for (let i = 0; i < list.data.length; i++) {
      const res = Interpreter.callAnonymousFunction(fun, [list.data[i]]);
      if (Type.isTrue(res)) {
        return Type.boolean(true);
      }
    }

    return Type.boolean(false);
  },
  // End any/2
  // Deps: []

  // Start filter/2
  "filter/2": function (fun, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.filter/2", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseErlangError(
        Interpreter.buildErlangErrorMsg(
          `{:bad_generator, ${Interpreter.inspect(list)}}`,
        ),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseErlangError(
        Interpreter.buildErlangErrorMsg(
          `{:bad_generator, ${Interpreter.inspect(list.data.at(-1))}}`,
        ),
      );
    }

    return Type.list(
      list.data.filter((elem) => {
        const result = Interpreter.callAnonymousFunction(fun, [elem]);

        if (!Type.isBoolean(result)) {
          Interpreter.raiseErlangError(
            Interpreter.buildErlangErrorMsg(
              `{:bad_filter, ${Interpreter.inspect(result)}}`,
            ),
          );
        }

        return Type.isTrue(result);
      }),
    );
  },
  // End filter/2
  // Deps: []

  // Start flatten/1
  "flatten/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatten/1", [list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatten/1", [list]),
      );
    }

    const data = list.data.reduce((acc, elem) => {
      if (Type.isList(elem)) {
        elem = Erlang_Lists["flatten/1"](elem);
        return acc.concat(elem.data);
      } else {
        return acc.concat(elem);
      }
    }, []);

    return Type.list(data);
  },
  // End flatten/1
  // Deps: []

  // Start foldl/3
  "foldl/3": function (fun, initialAcc, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.foldl/3", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseCaseClauseError(list);
    }

    if (!Type.isProperList(list)) {
      // Client-side error message is intentionally simplified.
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.foldl_1/3"),
      );
    }

    return list.data.reduce(
      (acc, elem) => Interpreter.callAnonymousFunction(fun, [elem, acc]),
      initialAcc,
    );
  },
  // End foldl/3
  // Deps: []

  // Start foldr/3
  "foldr/3": function (fun, initialAcc, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.foldr/3", arguments),
      );
    }

    if (!Type.isList(list) || !Type.isProperList(list)) {
      // Client-side error message is intentionally simplified.
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.foldr_1/3"),
      );
    }

    return list.data.reduceRight(
      (acc, elem) => Interpreter.callAnonymousFunction(fun, [elem, acc]),
      initialAcc,
    );
  },
  // End foldr/3
  // Deps: []

  // Start keydelete/3
  "keydelete/3": function (key, index, tuples) {
    if (!Type.isInteger(index)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(
          ":lists.keydelete/3",
          arguments,
        ),
      );
    }

    if (index.value < 1n) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(
          ":lists.keydelete/3",
          arguments,
        ),
      );
    }

    if (!Type.isProperList(tuples)) {
      const thirdArg = Type.isList(tuples) ? tuples.data.at(-1) : tuples;

      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.keydelete3/3", [
          key,
          index,
          thirdArg,
        ]),
      );
    }

    let result = tuples.data;

    for (let i = 0; i < tuples.data.length; i++) {
      const tuple = tuples.data[i];

      if (
        Type.isTuple(tuple) &&
        tuple.data.length >= index.value &&
        Interpreter.isEqual(tuple.data[Number(index.value) - 1], key)
      ) {
        result = [...tuples.data.slice(0, i), ...tuples.data.slice(i + 1)];
        break;
      }
    }

    return Type.list(result);
  },
  // End keydelete/3
  // Deps: []

  // Start keyfind/3
  "keyfind/3": (value, index, tuples) => {
    if (!Type.isInteger(index)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (index.value < 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    }

    if (!Type.isList(tuples)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    if (!Type.isProperList(tuples)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a proper list"),
      );
    }

    for (const tuple of tuples.data) {
      if (Type.isTuple(tuple)) {
        if (
          tuple.data.length >= index.value &&
          Interpreter.isEqual(tuple.data[Number(index.value) - 1], value)
        ) {
          return tuple;
        }
      }
    }

    return Type.boolean(false);
  },
  // End keyfind/3
  // Deps: []

  // Start keymember/3
  "keymember/3": (value, index, tuples) => {
    return Type.boolean(
      Type.isTuple(Erlang_Lists["keyfind/3"](value, index, tuples)),
    );
  },
  // End keymember/3
  // Deps: [:lists.keyfind/3]

  // Start keysort/2
  "keysort/2": (index, tuples) => {
    if (!Type.isInteger(index) || index.value <= 0n) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.keysort/2", [
          index,
          tuples,
        ]),
      );
    }

    if (!Type.isList(tuples)) {
      Interpreter.raiseCaseClauseError(tuples);
    }

    if (Type.isImproperList(tuples)) {
      if (tuples.data.length === 2) {
        Interpreter.raiseCaseClauseError(tuples);
      } else if (tuples.data.every((item) => Type.isTuple(item))) {
        // Client-side error message is intentionally simplified.
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.keysplit_1/8"),
        );
      } else {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(2, "not a tuple"),
        );
      }
    }

    if (tuples.data.length < 2) {
      return tuples;
    }

    const sorted = tuples.data.toSorted((tuple1, tuple2) =>
      Interpreter.compareTerms(
        Erlang["element/2"](index, tuple1),
        Erlang["element/2"](index, tuple2),
      ),
    );

    return Type.list(sorted);
  },
  // End keysort/2
  // Deps: [:erlang.element/2]

  // Start map/2
  "map/2": function (fun, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.map/2", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseCaseClauseError(list);
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.map_1/2"),
      );
    }

    return Type.list(
      list.data.map((elem) => Interpreter.callAnonymousFunction(fun, [elem])),
    );
  },
  // End map/2
  // Deps: []

  // Start member/2
  "member/2": (elem, list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    const isProperList = Type.isProperList(list);

    for (let i = 0; i < list.data.length; ++i) {
      if (Interpreter.isStrictlyEqual(list.data[i], elem)) {
        if (i < list.data.length - 1 || isProperList) {
          return Type.boolean(true);
        } else {
          Interpreter.raiseArgumentError(
            Interpreter.buildArgumentErrorMsg(2, "not a proper list"),
          );
        }
      }
    }

    if (!isProperList) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a proper list"),
      );
    }

    return Type.boolean(false);
  },
  // End member/2
  // Deps: []

  // Start min/1
  "min/1": (list) => {
    if (!Type.isList(list) || list.data.length === 0) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.min/1", [list]),
      );
    }

    // Notice that the error message says :lists.min/2 (not :lists.min/1)
    // :lists.min/2 is (probably) a private Erlang function that get's called by :lists.min/1
    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.min/2", [list]),
      );
    }

    let min = list.data[0];

    for (let i = 1; i < list.data.length; i++) {
      if (Interpreter.compareTerms(list.data[i], min) < 0) {
        min = list.data[i];
      }
    }

    return min;
  },
  // End min/1
  // Deps: []

  // Start reverse/1
  "reverse/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.reverse/1", [list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    return Type.list(list.data.toReversed());
  },
  // End reverse/1
  // Deps: []

  // Start reverse/2
  "reverse/2": (list, tail) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a proper list"),
      );
    }

    if (list.data.length === 0 && !Type.isList(tail)) {
      return tail;
    }

    const data = list.data
      .toReversed()
      .concat(Type.isList(tail) ? tail.data : [tail]);

    return Type.isProperList(tail) ? Type.list(data) : Type.improperList(data);
  },
  // End reverse/2
  // Deps: []

  // Start sort/1
  "sort/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.sort/1", [list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.split_1/5"),
      );
    }

    return Type.list(list.data.slice().sort(Interpreter.compareTerms));
  },
  // End sort/1
  // Deps: []

  // Client-side implementation uses simplified error details (for improper list with 2+ elements case)
  // Start sort/2
  "sort/2": (fun, list) => {
    // Only validate that the first argument is an anonymous function (type check)
    // Let arity validation happen naturally when the function is called
    if (!Type.isAnonymousFunction(fun)) {
      Interpreter.raiseError(
        "BadFunctionError",
        `expected a function, got: ${Interpreter.inspect(fun)}`,
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.sort/2", [fun, list]),
      );
    }

    if (!Type.isProperList(list)) {
      let errorMsg;

      // Match server behavior for improper lists:
      // - For lists with 1 element, raise error in :lists.sort/2
      // - For lists with 2+ elements, raise error in :lists.fsplit_1/6
      errorMsg =
        list.data.length <= 2
          ? Interpreter.buildFunctionClauseErrorMsg(":lists.sort/2", [
              fun,
              list,
            ])
          : Interpreter.buildFunctionClauseErrorMsg(":lists.fsplit_1/6");

      Interpreter.raiseFunctionClauseError(errorMsg);
    }

    return Type.list(
      list.data.slice().sort((a, b) => {
        const result = Interpreter.callAnonymousFunction(fun, [a, b]);
        return Type.isTrue(result) ? -1 : 1;
      }),
    );
  },
  // End sort/2
  // Deps: []
};

export default Erlang_Lists;
