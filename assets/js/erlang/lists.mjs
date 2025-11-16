"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Lists = {
  // Start all/2
  "all/2": function (fun, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.all/2", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.all/2", arguments),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.all_1/2"),
      );
    }

    for (const elem of list.data) {
      const result = Interpreter.callAnonymousFunction(fun, [elem]);

      if (!Type.isBoolean(result)) {
        Interpreter.raiseErlangError(
          Interpreter.buildErlangErrorMsg(
            `{:bad_filter, ${Interpreter.inspect(result)}}`,
          ),
        );
      }

      if (Type.isFalse(result)) {
        return Type.boolean(false);
      }
    }

    return Type.boolean(true);
  },
  // End all/2
  // Deps: []

  // Start any/2
  "any/2": function (fun, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.any/2", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.any/2", arguments),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.any_1/2"),
      );
    }

    for (const elem of list.data) {
      const result = Interpreter.callAnonymousFunction(fun, [elem]);

      if (!Type.isBoolean(result)) {
        Interpreter.raiseErlangError(
          Interpreter.buildErlangErrorMsg(
            `{:bad_filter, ${Interpreter.inspect(result)}}`,
          ),
        );
      }

      if (Type.isTrue(result)) {
        return Type.boolean(true);
      }
    }

    return Type.boolean(false);
  },
  // End any/2
  // Deps: []

  // Start duplicate/2
  "duplicate/2": (n, elem) => {
    if (!Type.isInteger(n)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.duplicate/2", [
          n,
          elem,
        ]),
      );
    }

    const nValue = Number(n.value);

    if (nValue < 0) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.duplicate/2", [
          n,
          elem,
        ]),
      );
    }

    const data = Array(nValue).fill(elem);
    return Type.list(data);
  },
  // End duplicate/2
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

  // Start flatmap/2
  "flatmap/2": function (fun, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatmap/2", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatmap/2", arguments),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatmap_1/2"),
      );
    }

    const data = list.data.reduce((acc, elem) => {
      const result = Interpreter.callAnonymousFunction(fun, [elem]);

      if (!Type.isList(result)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.flatmap_1/2"),
        );
      }

      if (!Type.isProperList(result)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.flatmap_1/2"),
        );
      }

      return acc.concat(result.data);
    }, []);

    return Type.list(data);
  },
  // End flatmap/2
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

  // Start foreach/2
  "foreach/2": function (fun, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.foreach/2", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.foreach/2", arguments),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.foreach_1/2"),
      );
    }

    for (const elem of list.data) {
      Interpreter.callAnonymousFunction(fun, [elem]);
    }

    return Type.atom("ok");
  },
  // End foreach/2
  // Deps: []

  // Start foldr/3
  "foldr/3": function (fun, initialAcc, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.foldr/3", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseCaseClauseError(list);
    }

    if (!Type.isProperList(list)) {
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

  // Start max/1
  "max/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.max/1", [list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.max/1", [list]),
      );
    }

    if (list.data.length === 0) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "[]"),
      );
    }

    return list.data.reduce((max, elem) => {
      const comparison = Interpreter.compareTerms(elem, max);
      return comparison === 1 ? elem : max;
    });
  },
  // End max/1
  // Deps: []

  // Start min/1
  "min/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.min/1", [list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.min/1", [list]),
      );
    }

    if (list.data.length === 0) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "[]"),
      );
    }

    return list.data.reduce((min, elem) => {
      const comparison = Interpreter.compareTerms(elem, min);
      return comparison === -1 ? elem : min;
    });
  },
  // End min/1
  // Deps: []

  // Start nth/2
  "nth/2": (n, list) => {
    if (!Type.isInteger(n)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.nth/2", [n, list]),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.nth/2", [n, list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.nth/2", [n, list]),
      );
    }

    const index = Number(n.value);

    if (index < 1 || index > list.data.length) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.nth/2", [n, list]),
      );
    }

    return list.data[index - 1];
  },
  // End nth/2
  // Deps: []

  // Start nthtail/2
  "nthtail/2": (n, list) => {
    if (!Type.isInteger(n)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.nthtail/2", [n, list]),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.nthtail/2", [n, list]),
      );
    }

    const index = Number(n.value);

    if (index < 0) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.nthtail/2", [n, list]),
      );
    }

    // For nthtail, we need to traverse the list n times
    let currentList = list;
    for (let i = 0; i < index; i++) {
      if (!Type.isList(currentList) || currentList.data.length === 0) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.nthtail/2", [
            n,
            list,
          ]),
        );
      }
      // Get the tail
      if (currentList.data.length === 1) {
        // Last element, return the tail (which might be improper)
        currentList = currentList.tail || Type.list([]);
      } else {
        currentList = Type.list(currentList.data.slice(1));
        if (currentList.data.length === 0 && list.tail) {
          currentList = list.tail;
        }
      }
    }

    return currentList;
  },
  // End nthtail/2
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

    return Type.list(list.data.sort(Interpreter.compareTerms));
  },
  // End sort/1
  // Deps: []

  // Start split/2
  "split/2": (n, list) => {
    if (!Type.isInteger(n)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.split/2", [n, list]),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.split/2", [n, list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.split/2", [n, list]),
      );
    }

    const index = Number(n.value);

    if (index < 0 || index > list.data.length) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.split/2", [n, list]),
      );
    }

    const left = Type.list(list.data.slice(0, index));
    const right = Type.list(list.data.slice(index));

    return Type.tuple([left, right]);
  },
  // End split/2
  // Deps: []

  // Start sublist/2
  "sublist/2": (list, length) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist/2", [
          list,
          length,
        ]),
      );
    }

    if (!Type.isInteger(length)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist/2", [
          list,
          length,
        ]),
      );
    }

    const len = Number(length.value);

    if (len < 0) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist/2", [
          list,
          length,
        ]),
      );
    }

    // Validate proper list while taking elements
    const result = [];
    for (let i = 0; i < Math.min(len, list.data.length); i++) {
      result.push(list.data[i]);
    }

    // If we took fewer elements than requested, check if list is proper
    if (result.length < len && !Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist_2/4"),
      );
    }

    return Type.list(result);
  },
  // End sublist/2
  // Deps: []

  // Start sublist/3
  "sublist/3": (list, start, length) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist/3", [
          list,
          start,
          length,
        ]),
      );
    }

    if (!Type.isInteger(start)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist/3", [
          list,
          start,
          length,
        ]),
      );
    }

    if (!Type.isInteger(length)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist/3", [
          list,
          start,
          length,
        ]),
      );
    }

    const startIdx = Number(start.value);
    const len = Number(length.value);

    if (startIdx < 1 || len < 0) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist/3", [
          list,
          start,
          length,
        ]),
      );
    }

    // Check if we need to validate the list is proper
    const needsProperCheck = startIdx > list.data.length;

    if (needsProperCheck && !Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.sublist_3/5"),
      );
    }

    // Take elements from start position (1-indexed)
    const result = [];
    const actualStart = Math.min(startIdx - 1, list.data.length);
    const actualEnd = Math.min(actualStart + len, list.data.length);

    for (let i = actualStart; i < actualEnd; i++) {
      result.push(list.data[i]);
    }

    return Type.list(result);
  },
  // End sublist/3
  // Deps: []

  // Start takewhile/2
  "takewhile/2": function (fun, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.takewhile/2", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.takewhile/2", arguments),
      );
    }

    const result = [];

    for (let i = 0; i < list.data.length; i++) {
      const elem = list.data[i];
      const testResult = Interpreter.callAnonymousFunction(fun, [elem]);

      if (!Type.isBoolean(testResult)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.takewhile_2/4"),
        );
      }

      if (Type.isFalse(testResult)) {
        break;
      }

      result.push(elem);
    }

    // If we exhausted the list, validate it's proper
    if (result.length === list.data.length && !Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.takewhile_2/4"),
      );
    }

    return Type.list(result);
  },
  // End takewhile/2
  // Deps: []

  // Start dropwhile/2
  "dropwhile/2": function (fun, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.dropwhile/2", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.dropwhile/2", arguments),
      );
    }

    let dropCount = 0;

    for (let i = 0; i < list.data.length; i++) {
      const elem = list.data[i];
      const testResult = Interpreter.callAnonymousFunction(fun, [elem]);

      if (!Type.isBoolean(testResult)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.dropwhile_2/4"),
        );
      }

      if (Type.isFalse(testResult)) {
        break;
      }

      dropCount++;
    }

    // If we dropped everything, validate it's proper
    if (dropCount === list.data.length && !Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.dropwhile_2/4"),
      );
    }

    return Type.list(list.data.slice(dropCount));
  },
  // End dropwhile/2
  // Deps: []
};

export default Erlang_Lists;
