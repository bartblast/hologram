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

  // Start append/1
  "append/1": (listOfLists) => {
    if (!Type.isList(listOfLists)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.append/1", [
          listOfLists,
        ]),
      );
    }

    if (!Type.isProperList(listOfLists)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.append/1", [
          listOfLists,
        ]),
      );
    }

    const result = [];

    for (const list of listOfLists.data) {
      if (!Type.isList(list)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.append_1/2"),
        );
      }

      if (!Type.isProperList(list)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.append_1/2"),
        );
      }

      result.push(...list.data);
    }

    return Type.list(result);
  },
  // End append/1
  // Deps: []

  // Start append/2
  "append/2": (list1, list2) => {
    if (!Type.isList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.append/2", [
          list1,
          list2,
        ]),
      );
    }

    if (!Type.isProperList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.append/2", [
          list1,
          list2,
        ]),
      );
    }

    if (!Type.isList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.append/2", [
          list1,
          list2,
        ]),
      );
    }

    // list2 can be improper - we preserve that
    const result = Type.list([...list1.data, ...list2.data]);
    if (list2.tail) {
      result.tail = list2.tail;
    }

    return result;
  },
  // End append/2
  // Deps: []

  // Start concat/1
  "concat/1": (listOfAtoms) => {
    if (!Type.isList(listOfAtoms)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.concat/1", [
          listOfAtoms,
        ]),
      );
    }

    if (!Type.isProperList(listOfAtoms)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.concat/1", [
          listOfAtoms,
        ]),
      );
    }

    let result = "";

    for (const elem of listOfAtoms.data) {
      if (Type.isAtom(elem)) {
        result += elem.value;
      } else if (Type.isBitstring(elem)) {
        result += elem.text || "";
      } else if (Type.isInteger(elem)) {
        result += elem.value.toString();
      } else if (Type.isFloat(elem)) {
        result += elem.value.toString();
      } else {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.concat_1/2"),
        );
      }
    }

    return Type.atom(result);
  },
  // End concat/1
  // Deps: []

  // Start delete/2
  "delete/2": (elem, list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.delete/2", [
          elem,
          list,
        ]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.delete/2", [
          elem,
          list,
        ]),
      );
    }

    const result = [];
    let deleted = false;

    for (const item of list.data) {
      if (!deleted && Interpreter.isStrictlyEqual(item, elem)) {
        deleted = true;
      } else {
        result.push(item);
      }
    }

    return Type.list(result);
  },
  // End delete/2
  // Deps: []

  // Start droplast/1
  "droplast/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.droplast/1", [list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.droplast/1", [list]),
      );
    }

    if (list.data.length === 0) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.droplast/1", [list]),
      );
    }

    return Type.list(list.data.slice(0, -1));
  },
  // End droplast/1
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

  // Start enumerate/1
  "enumerate/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.enumerate/1", [list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.enumerate_1/3"),
      );
    }

    const result = [];
    for (let i = 0; i < list.data.length; i++) {
      result.push(
        Type.tuple([Type.integer(BigInt(i + 1)), list.data[i]]),
      );
    }

    return Type.list(result);
  },
  // End enumerate/1
  // Deps: []

  // Start enumerate/2
  "enumerate/2": (indexOrList, listOrIndex) => {
    // Can be called as enumerate(Index, List) or enumerate(List, Fun)
    // Check if first arg is integer (Index, List) or list (List, Fun)
    if (Type.isInteger(indexOrList) && Type.isList(listOrIndex)) {
      // enumerate(Index, List) - start from Index
      const startIndex = indexOrList;
      const list = listOrIndex;

      if (!Type.isProperList(list)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.enumerate_1/3"),
        );
      }

      const result = [];
      let currentIndex = Number(startIndex.value);
      for (let i = 0; i < list.data.length; i++) {
        result.push(
          Type.tuple([Type.integer(BigInt(currentIndex)), list.data[i]]),
        );
        currentIndex++;
      }

      return Type.list(result);
    } else if (Type.isList(indexOrList) && Type.isAnonymousFunction(listOrIndex)) {
      // enumerate(List, Fun) - apply function to {Index, Element}
      const list = indexOrList;
      const fun = listOrIndex;

      if (fun.arity !== 1) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.enumerate/2", [
            indexOrList,
            listOrIndex,
          ]),
        );
      }

      if (!Type.isProperList(list)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.enumerate_1/3"),
        );
      }

      const result = [];
      for (let i = 0; i < list.data.length; i++) {
        const indexedElem = Type.tuple([Type.integer(BigInt(i + 1)), list.data[i]]);
        result.push(Interpreter.callAnonymousFunction(fun, [indexedElem]));
      }

      return Type.list(result);
    } else {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.enumerate/2", [
          indexOrList,
          listOrIndex,
        ]),
      );
    }
  },
  // End enumerate/2
  // Deps: []

  // Start enumerate/3
  "enumerate/3": (index, list, step) => {
    if (!Type.isInteger(index)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.enumerate/3", [
          index,
          list,
          step,
        ]),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.enumerate/3", [
          index,
          list,
          step,
        ]),
      );
    }

    if (!Type.isInteger(step)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.enumerate/3", [
          index,
          list,
          step,
        ]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.enumerate_1/3"),
      );
    }

    const result = [];
    let currentIndex = Number(index.value);
    const stepValue = Number(step.value);

    for (let i = 0; i < list.data.length; i++) {
      result.push(
        Type.tuple([Type.integer(BigInt(currentIndex)), list.data[i]]),
      );
      currentIndex += stepValue;
    }

    return Type.list(result);
  },
  // End enumerate/3
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

  // Start filtermap/2
  "filtermap/2": function (fun, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.filtermap/2", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.filtermap/2", arguments),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.filtermap_1/3"),
      );
    }

    const result = [];
    for (const elem of list.data) {
      const funResult = Interpreter.callAnonymousFunction(fun, [elem]);

      if (Type.isTrue(funResult)) {
        result.push(elem);
      } else if (Type.isTuple(funResult)) {
        if (
          funResult.data.length === 2 &&
          Type.isAtom(funResult.data[0]) &&
          funResult.data[0].value === "true"
        ) {
          result.push(funResult.data[1]);
        } else {
          Interpreter.raiseFunctionClauseError(
            Interpreter.buildFunctionClauseErrorMsg(":lists.filtermap_1/3"),
          );
        }
      } else if (!Type.isFalse(funResult)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.filtermap_1/3"),
        );
      }
    }

    return Type.list(result);
  },
  // End filtermap/2
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

  // Start flatten/2
  "flatten/2": (list, tail) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatten/2", [
          list,
          tail,
        ]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatten/2", [
          list,
          tail,
        ]),
      );
    }

    const flattened = Erlang_Lists["flatten/1"](list);

    if (!Type.isList(tail)) {
      return Erlang_Lists["append/2"](flattened, Type.list([tail]));
    }

    return Erlang_Lists["append/2"](flattened, tail);
  },
  // End flatten/2
  // Deps: [:lists.flatten/1, :lists.append/2]

  // Start flatlength/1
  "flatlength/1": (deepList) => {
    if (!Type.isList(deepList)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatlength/1", [deepList]),
      );
    }

    if (!Type.isProperList(deepList)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatlength/1", [deepList]),
      );
    }

    let count = 0;

    const countElements = (list) => {
      for (const elem of list.data) {
        if (Type.isList(elem) && Type.isProperList(elem)) {
          countElements(elem);
        } else {
          count++;
        }
      }
    };

    countElements(deepList);
    return Type.integer(BigInt(count));
  },
  // End flatlength/1
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

  // Start keydelete/3
  "keydelete/3": (value, index, tuples) => {
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

    const result = [];
    let deleted = false;

    for (const tuple of tuples.data) {
      if (
        !deleted &&
        Type.isTuple(tuple) &&
        tuple.data.length >= index.value &&
        Interpreter.isEqual(tuple.data[Number(index.value) - 1], value)
      ) {
        deleted = true;
      } else {
        result.push(tuple);
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

  // Start keymap/3
  "keymap/3": function (fun, index, tuples) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a function of arity 1"),
      );
    }

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

    const indexNum = Number(index.value) - 1;
    const result = [];

    for (const tuple of tuples.data) {
      if (!Type.isTuple(tuple) || tuple.data.length <= indexNum) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(3, "list element is not a tuple or tuple is too small"),
        );
      }

      const newValue = Interpreter.callAnonymousFunction(fun, [tuple.data[indexNum]]);
      const newTupleData = tuple.data.slice();
      newTupleData[indexNum] = newValue;
      result.push(Type.tuple(newTupleData));
    }

    return Type.list(result);
  },
  // End keymap/3
  // Deps: []

  // Start keyreplace/4
  "keyreplace/4": (value, index, tuples, newTuple) => {
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

    const result = [];
    let replaced = false;

    for (const tuple of tuples.data) {
      if (
        !replaced &&
        Type.isTuple(tuple) &&
        tuple.data.length >= index.value &&
        Interpreter.isEqual(tuple.data[Number(index.value) - 1], value)
      ) {
        result.push(newTuple);
        replaced = true;
      } else {
        result.push(tuple);
      }
    }

    return Type.list(result);
  },
  // End keyreplace/4
  // Deps: []

  // Start keysort/2
  "keysort/2": (index, tuples) => {
    if (!Type.isInteger(index)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (index.value < 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    }

    if (!Type.isList(tuples)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    if (!Type.isProperList(tuples)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a proper list"),
      );
    }

    const indexNum = Number(index.value) - 1;

    return Type.list(
      tuples.data.slice().sort((a, b) => {
        if (!Type.isTuple(a) || a.data.length <= indexNum) {
          Interpreter.raiseArgumentError(
            Interpreter.buildArgumentErrorMsg(2, "list element is not a tuple or tuple is too small"),
          );
        }
        if (!Type.isTuple(b) || b.data.length <= indexNum) {
          Interpreter.raiseArgumentError(
            Interpreter.buildArgumentErrorMsg(2, "list element is not a tuple or tuple is too small"),
          );
        }
        return Interpreter.compareTerms(a.data[indexNum], b.data[indexNum]);
      }),
    );
  },
  // End keysort/2
  // Deps: []

  // Start keysearch/3
  "keysearch/3": (value, index, tuples) => {
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

    const indexNum = Number(index.value) - 1;

    for (const tuple of tuples.data) {
      if (!Type.isTuple(tuple)) {
        continue;
      }

      if (tuple.data.length <= indexNum) {
        continue;
      }

      if (Interpreter.isEqual(tuple.data[indexNum], value)) {
        return Type.tuple([Type.atom("value"), tuple]);
      }
    }

    return Type.atom("false");
  },
  // End keysearch/3
  // Deps: []

  // Start keytake/3
  "keytake/3": (value, index, tuples) => {
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

    const result = [];
    let foundTuple = null;

    for (const tuple of tuples.data) {
      if (
        foundTuple === null &&
        Type.isTuple(tuple) &&
        tuple.data.length >= index.value &&
        Interpreter.isEqual(tuple.data[Number(index.value) - 1], value)
      ) {
        foundTuple = tuple;
      } else {
        result.push(tuple);
      }
    }

    if (foundTuple !== null) {
      return Type.tuple([Type.atom("value"), foundTuple, Type.list(result)]);
    }

    return Type.boolean(false);
  },
  // End keytake/3
  // Deps: []

  // Start keymerge/3
  "keymerge/3": (index, tuples1, tuples2) => {
    if (!Type.isInteger(index)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (index.value < 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    }

    if (!Type.isList(tuples1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    if (!Type.isList(tuples2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    if (!Type.isProperList(tuples1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a proper list"),
      );
    }

    if (!Type.isProperList(tuples2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a proper list"),
      );
    }

    const indexNum = Number(index.value) - 1;
    const result = [];
    let i = 0;
    let j = 0;

    while (i < tuples1.data.length && j < tuples2.data.length) {
      const t1 = tuples1.data[i];
      const t2 = tuples2.data[j];

      if (!Type.isTuple(t1) || t1.data.length <= indexNum) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(2, "list element is not a tuple or tuple is too small"),
        );
      }

      if (!Type.isTuple(t2) || t2.data.length <= indexNum) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(3, "list element is not a tuple or tuple is too small"),
        );
      }

      if (Interpreter.compareTerms(t1.data[indexNum], t2.data[indexNum]) <= 0) {
        result.push(t1);
        i++;
      } else {
        result.push(t2);
        j++;
      }
    }

    while (i < tuples1.data.length) {
      result.push(tuples1.data[i]);
      i++;
    }

    while (j < tuples2.data.length) {
      result.push(tuples2.data[j]);
      j++;
    }

    return Type.list(result);
  },
  // End keymerge/3
  // Deps: []

  // Start keystore/4
  "keystore/4": (value, index, tuples, newTuple) => {
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

    const result = [];
    let stored = false;

    for (const tuple of tuples.data) {
      if (
        !stored &&
        Type.isTuple(tuple) &&
        tuple.data.length >= index.value &&
        Interpreter.isEqual(tuple.data[Number(index.value) - 1], value)
      ) {
        result.push(newTuple);
        stored = true;
      } else {
        result.push(tuple);
      }
    }

    if (!stored) {
      result.push(newTuple);
    }

    return Type.list(result);
  },
  // End keystore/4
  // Deps: []

  // Start join/2
  "join/2": (sep, list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.join/2", [sep, list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.join/2", [sep, list]),
      );
    }

    if (list.data.length === 0) {
      return Type.list([]);
    }

    const result = [];
    for (let i = 0; i < list.data.length; i++) {
      result.push(list.data[i]);
      if (i < list.data.length - 1) {
        result.push(sep);
      }
    }

    return Type.list(result);
  },
  // End join/2
  // Deps: []

  // Start last/1
  "last/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.last/1", [list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.last/1", [list]),
      );
    }

    if (list.data.length === 0) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.last/1", [list]),
      );
    }

    return list.data[list.data.length - 1];
  },
  // End last/1
  // Deps: []

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

  // Start mapfoldl/3
  "mapfoldl/3": function (fun, acc, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.mapfoldl/3", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.mapfoldl/3", arguments),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.mapfoldl_1/3"),
      );
    }

    const result = [];
    let currentAcc = acc;

    for (const elem of list.data) {
      const funResult = Interpreter.callAnonymousFunction(fun, [elem, currentAcc]);

      if (!Type.isTuple(funResult) || funResult.data.length !== 2) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.mapfoldl_1/3"),
        );
      }

      result.push(funResult.data[0]);
      currentAcc = funResult.data[1];
    }

    return Type.tuple([Type.list(result), currentAcc]);
  },
  // End mapfoldl/3
  // Deps: []

  // Start mapfoldr/3
  "mapfoldr/3": function (fun, acc, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.mapfoldr/3", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.mapfoldr/3", arguments),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.mapfoldr_1/3"),
      );
    }

    const result = [];
    let currentAcc = acc;

    for (let i = list.data.length - 1; i >= 0; i--) {
      const funResult = Interpreter.callAnonymousFunction(fun, [list.data[i], currentAcc]);

      if (!Type.isTuple(funResult) || funResult.data.length !== 2) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.mapfoldr_1/3"),
        );
      }

      result.unshift(funResult.data[0]);
      currentAcc = funResult.data[1];
    }

    return Type.tuple([Type.list(result), currentAcc]);
  },
  // End mapfoldr/3
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

  // Start partition/2
  "partition/2": function (fun, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.partition/2", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.partition/2", arguments),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.partition_1/4"),
      );
    }

    const satisfying = [];
    const notSatisfying = [];

    for (const elem of list.data) {
      const result = Interpreter.callAnonymousFunction(fun, [elem]);

      if (!Type.isBoolean(result)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.partition_1/4"),
        );
      }

      if (Type.isTrue(result)) {
        satisfying.push(elem);
      } else {
        notSatisfying.push(elem);
      }
    }

    return Type.tuple([Type.list(satisfying), Type.list(notSatisfying)]);
  },
  // End partition/2
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

  // Start merge/1
  "merge/1": (listOfLists) => {
    if (!Type.isList(listOfLists)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge/1", [listOfLists]),
      );
    }

    if (!Type.isProperList(listOfLists)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge_1/2"),
      );
    }

    if (listOfLists.data.length === 0) {
      return Type.list([]);
    }

    let result = listOfLists.data[0];

    if (!Type.isList(result)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge_1/2"),
      );
    }

    for (let i = 1; i < listOfLists.data.length; i++) {
      result = Erlang_Lists["merge/2"](result, listOfLists.data[i]);
    }

    return result;
  },
  // End merge/1
  // Deps: [:lists.merge/2]

  // Start merge/2
  "merge/2": (list1, list2) => {
    if (!Type.isList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge/2", [
          list1,
          list2,
        ]),
      );
    }

    if (!Type.isList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge/2", [
          list1,
          list2,
        ]),
      );
    }

    if (!Type.isProperList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge_1/3"),
      );
    }

    if (!Type.isProperList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge_1/3"),
      );
    }

    const result = [];
    let i = 0;
    let j = 0;

    while (i < list1.data.length && j < list2.data.length) {
      if (Interpreter.compareTerms(list1.data[i], list2.data[j]) <= 0) {
        result.push(list1.data[i]);
        i++;
      } else {
        result.push(list2.data[j]);
        j++;
      }
    }

    while (i < list1.data.length) {
      result.push(list1.data[i]);
      i++;
    }

    while (j < list2.data.length) {
      result.push(list2.data[j]);
      j++;
    }

    return Type.list(result);
  },
  // End merge/2
  // Deps: []

  // Start merge3/3
  "merge3/3": (list1, list2, list3) => {
    if (!Type.isList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge3/3", [
          list1,
          list2,
          list3,
        ]),
      );
    }

    if (!Type.isList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge3/3", [
          list1,
          list2,
          list3,
        ]),
      );
    }

    if (!Type.isList(list3)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge3/3", [
          list1,
          list2,
          list3,
        ]),
      );
    }

    if (!Type.isProperList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge3_1/4"),
      );
    }

    if (!Type.isProperList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge3_1/4"),
      );
    }

    if (!Type.isProperList(list3)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge3_1/4"),
      );
    }

    // Merge list1 and list2 first
    const merged12 = Erlang_Lists["merge/2"](list1, list2);
    // Then merge result with list3
    return Erlang_Lists["merge/2"](merged12, list3);
  },
  // End merge3/3
  // Deps: [:lists.merge/2]

  // Start merge/3
  "merge/3": function (fun, list1, list2) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge/3", arguments),
      );
    }

    if (!Type.isList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge/3", arguments),
      );
    }

    if (!Type.isList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge/3", arguments),
      );
    }

    if (!Type.isProperList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge_1/4"),
      );
    }

    if (!Type.isProperList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.merge_1/4"),
      );
    }

    const result = [];
    let i = 0;
    let j = 0;

    while (i < list1.data.length && j < list2.data.length) {
      const comp = Interpreter.callAnonymousFunction(fun, [
        list1.data[i],
        list2.data[j],
      ]);

      if (!Type.isBoolean(comp)) {
        Interpreter.raiseErlangError(
          Interpreter.buildErlangErrorMsg(
            `{:bad_generator, ${Interpreter.inspect(comp)}}`,
          ),
        );
      }

      if (Type.isTrue(comp)) {
        result.push(list1.data[i]);
        i++;
      } else {
        result.push(list2.data[j]);
        j++;
      }
    }

    while (i < list1.data.length) {
      result.push(list1.data[i]);
      i++;
    }

    while (j < list2.data.length) {
      result.push(list2.data[j]);
      j++;
    }

    return Type.list(result);
  },
  // End merge/3
  // Deps: []

  // Start prefix/2
  "prefix/2": (prefix, list) => {
    if (!Type.isList(prefix)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.prefix/2", [
          prefix,
          list,
        ]),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.prefix/2", [
          prefix,
          list,
        ]),
      );
    }

    if (!Type.isProperList(prefix)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.prefix_1/2"),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.prefix_1/2"),
      );
    }

    if (prefix.data.length > list.data.length) {
      return Type.boolean(false);
    }

    for (let i = 0; i < prefix.data.length; i++) {
      if (!Interpreter.isEqual(prefix.data[i], list.data[i])) {
        return Type.boolean(false);
      }
    }

    return Type.boolean(true);
  },
  // End prefix/2
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

  // Start search/2
  "search/2": function (fun, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.search/2", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.search/2", arguments),
      );
    }

    for (const elem of list.data) {
      const result = Interpreter.callAnonymousFunction(fun, [elem]);

      if (!Type.isBoolean(result) && !Type.isTuple(result)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.search_1/2"),
        );
      }

      // Check if it's {true, Value} tuple
      if (Type.isTuple(result)) {
        if (
          result.data.length === 2 &&
          Type.isAtom(result.data[0]) &&
          result.data[0].value === "true"
        ) {
          return Type.tuple([Type.atom("value"), result.data[1]]);
        }
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.search_1/2"),
        );
      }

      if (Type.isTrue(result)) {
        return Type.tuple([Type.atom("value"), elem]);
      }
    }

    // If we exhausted the list, validate it's proper
    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.search_1/2"),
      );
    }

    return Type.boolean(false);
  },
  // End search/2
  // Deps: []

  // Start seq/2
  "seq/2": (from, to) => {
    if (!Type.isInteger(from)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.seq/2", [from, to]),
      );
    }

    if (!Type.isInteger(to)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.seq/2", [from, to]),
      );
    }

    const fromVal = Number(from.value);
    const toVal = Number(to.value);

    if (fromVal > toVal) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.seq_loop/3"),
      );
    }

    const result = [];
    for (let i = fromVal; i <= toVal; i++) {
      result.push(Type.integer(i));
    }

    return Type.list(result);
  },
  // End seq/2
  // Deps: []

  // Start seq/3
  "seq/3": (from, to, incr) => {
    if (!Type.isInteger(from)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.seq/3", [
          from,
          to,
          incr,
        ]),
      );
    }

    if (!Type.isInteger(to)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.seq/3", [
          from,
          to,
          incr,
        ]),
      );
    }

    if (!Type.isInteger(incr)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.seq/3", [
          from,
          to,
          incr,
        ]),
      );
    }

    const fromVal = Number(from.value);
    const toVal = Number(to.value);
    const incrVal = Number(incr.value);

    if (incrVal === 0) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "zero"),
      );
    }

    if (
      (incrVal > 0 && fromVal > toVal) ||
      (incrVal < 0 && fromVal < toVal)
    ) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.seq_loop/4"),
      );
    }

    const result = [];
    if (incrVal > 0) {
      for (let i = fromVal; i <= toVal; i += incrVal) {
        result.push(Type.integer(i));
      }
    } else {
      for (let i = fromVal; i >= toVal; i += incrVal) {
        result.push(Type.integer(i));
      }
    }

    return Type.list(result);
  },
  // End seq/3
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

  // Start sort/2
  "sort/2": function (fun, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.sort/2", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.sort/2", arguments),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.sort_1/3"),
      );
    }

    return Type.list(
      list.data.slice().sort((a, b) => {
        const result = Interpreter.callAnonymousFunction(fun, [a, b]);

        if (!Type.isBoolean(result)) {
          Interpreter.raiseFunctionClauseError(
            Interpreter.buildFunctionClauseErrorMsg(":lists.sort_1/3"),
          );
        }

        return Type.isTrue(result) ? -1 : 1;
      }),
    );
  },
  // End sort/2
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

  // Start splitwith/2
  "splitwith/2": function (predicate, list) {
    if (!Type.isAnonymousFunction(predicate) || predicate.arity !== 1) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.splitwith/2", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.splitwith/2", arguments),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.splitwith_1/4"),
      );
    }

    const satisfying = [];
    let i = 0;

    for (; i < list.data.length; i++) {
      const result = Interpreter.callAnonymousFunction(predicate, [list.data[i]]);

      if (!Type.isTrue(result)) {
        break;
      }
      satisfying.push(list.data[i]);
    }

    const notSatisfying = list.data.slice(i);

    return Type.tuple([Type.list(satisfying), Type.list(notSatisfying)]);
  },
  // End splitwith/2
  // Deps: []

  // Start sum/1
  "sum/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.sum/1", [list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.sum/1", [list]),
      );
    }

    let sum = 0n;
    let hasFloat = false;

    for (const elem of list.data) {
      if (Type.isInteger(elem)) {
        if (hasFloat) {
          sum += Number(elem.value);
        } else {
          sum += elem.value;
        }
      } else if (Type.isFloat(elem)) {
        if (!hasFloat) {
          sum = Number(sum);
          hasFloat = true;
        }
        sum += elem.value;
      } else {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(1, "not a list of numbers"),
        );
      }
    }

    return hasFloat ? Type.float(sum) : Type.integer(sum);
  },
  // End sum/1
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

  // Start subtract/2
  "subtract/2": (list1, list2) => {
    if (!Type.isList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.subtract/2", [
          list1,
          list2,
        ]),
      );
    }

    if (!Type.isList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.subtract/2", [
          list1,
          list2,
        ]),
      );
    }

    if (!Type.isProperList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.subtract_1/3"),
      );
    }

    if (!Type.isProperList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.subtract_1/3"),
      );
    }

    const result = [];
    const list2Copy = list2.data.slice();

    for (const elem of list1.data) {
      let found = false;
      for (let i = 0; i < list2Copy.length; i++) {
        if (Interpreter.isEqual(elem, list2Copy[i])) {
          list2Copy.splice(i, 1);
          found = true;
          break;
        }
      }
      if (!found) {
        result.push(elem);
      }
    }

    return Type.list(result);
  },
  // End subtract/2
  // Deps: []

  // Start suffix/2
  "suffix/2": (suffix, list) => {
    if (!Type.isList(suffix)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.suffix/2", [
          suffix,
          list,
        ]),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.suffix/2", [
          suffix,
          list,
        ]),
      );
    }

    if (!Type.isProperList(suffix)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.suffix_1/2"),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.suffix_1/2"),
      );
    }

    if (suffix.data.length > list.data.length) {
      return Type.boolean(false);
    }

    const offset = list.data.length - suffix.data.length;
    for (let i = 0; i < suffix.data.length; i++) {
      if (!Interpreter.isEqual(suffix.data[i], list.data[offset + i])) {
        return Type.boolean(false);
      }
    }

    return Type.boolean(true);
  },
  // End suffix/2
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

  // Start unzip/1
  "unzip/1": (listOfTuples) => {
    if (!Type.isList(listOfTuples)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.unzip/1", [
          listOfTuples,
        ]),
      );
    }

    if (!Type.isProperList(listOfTuples)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.unzip/1", [
          listOfTuples,
        ]),
      );
    }

    const list1 = [];
    const list2 = [];

    for (const tuple of listOfTuples.data) {
      if (!Type.isTuple(tuple) || tuple.data.length !== 2) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.unzip_1/3"),
        );
      }

      list1.push(tuple.data[0]);
      list2.push(tuple.data[1]);
    }

    return Type.tuple([Type.list(list1), Type.list(list2)]);
  },
  // End unzip/1
  // Deps: []

  // Start unzip3/1
  "unzip3/1": (tuples) => {
    if (!Type.isList(tuples)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.unzip3/1", [tuples]),
      );
    }

    if (!Type.isProperList(tuples)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.unzip3_1/4"),
      );
    }

    const list1 = [];
    const list2 = [];
    const list3 = [];

    for (const tuple of tuples.data) {
      if (!Type.isTuple(tuple) || tuple.data.length !== 3) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.unzip3_1/4"),
        );
      }
      list1.push(tuple.data[0]);
      list2.push(tuple.data[1]);
      list3.push(tuple.data[2]);
    }

    return Type.tuple([Type.list(list1), Type.list(list2), Type.list(list3)]);
  },
  // End unzip3/1
  // Deps: []

  // Start uniq/1
  "uniq/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.uniq/1", [list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.uniq_1/2"),
      );
    }

    if (list.data.length === 0) {
      return Type.list([]);
    }

    const result = [list.data[0]];

    for (let i = 1; i < list.data.length; i++) {
      if (!Interpreter.isEqual(list.data[i], list.data[i - 1])) {
        result.push(list.data[i]);
      }
    }

    return Type.list(result);
  },
  // End uniq/1
  // Deps: []

  // Start uniq/2
  "uniq/2": function (fun, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.uniq/2", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.uniq/2", arguments),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.uniq_2/3"),
      );
    }

    if (list.data.length === 0) {
      return Type.list([]);
    }

    const result = [list.data[0]];

    for (let i = 1; i < list.data.length; i++) {
      const isEqual = Interpreter.callAnonymousFunction(fun, [
        list.data[i],
        list.data[i - 1],
      ]);

      if (!Type.isBoolean(isEqual)) {
        Interpreter.raiseErlangError(
          Interpreter.buildErlangErrorMsg(
            `{:bad_generator, ${Interpreter.inspect(isEqual)}}`,
          ),
        );
      }

      if (Type.isFalse(isEqual)) {
        result.push(list.data[i]);
      }
    }

    return Type.list(result);
  },
  // End uniq/2
  // Deps: []

  // Start ukeysort/2
  "ukeysort/2": (index, tuples) => {
    if (!Type.isInteger(index)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (index.value < 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    }

    if (!Type.isList(tuples)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    if (!Type.isProperList(tuples)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a proper list"),
      );
    }

    const sorted = Erlang_Lists["keysort/2"](index, tuples);
    const indexNum = Number(index.value) - 1;

    if (sorted.data.length === 0) {
      return Type.list([]);
    }

    const result = [sorted.data[0]];
    for (let i = 1; i < sorted.data.length; i++) {
      const prev = sorted.data[i - 1];
      const curr = sorted.data[i];

      if (!Interpreter.isEqual(prev.data[indexNum], curr.data[indexNum])) {
        result.push(curr);
      }
    }

    return Type.list(result);
  },
  // End ukeysort/2
  // Deps: [:lists.keysort/2]

  // Start ukeymerge/3
  "ukeymerge/3": (index, tuples1, tuples2) => {
    if (!Type.isInteger(index)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (index.value < 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    }

    if (!Type.isList(tuples1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    if (!Type.isList(tuples2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    if (!Type.isProperList(tuples1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a proper list"),
      );
    }

    if (!Type.isProperList(tuples2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a proper list"),
      );
    }

    const indexNum = Number(index.value) - 1;
    const result = [];
    let i = 0;
    let j = 0;

    while (i < tuples1.data.length && j < tuples2.data.length) {
      const t1 = tuples1.data[i];
      const t2 = tuples2.data[j];

      if (!Type.isTuple(t1) || t1.data.length <= indexNum) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(2, "list element is not a tuple or tuple is too small"),
        );
      }

      if (!Type.isTuple(t2) || t2.data.length <= indexNum) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(3, "list element is not a tuple or tuple is too small"),
        );
      }

      const comp = Interpreter.compareTerms(t1.data[indexNum], t2.data[indexNum]);

      if (comp < 0) {
        result.push(t1);
        i++;
      } else if (comp > 0) {
        result.push(t2);
        j++;
      } else {
        result.push(t1);
        i++;
        j++;
      }
    }

    while (i < tuples1.data.length) {
      result.push(tuples1.data[i]);
      i++;
    }

    while (j < tuples2.data.length) {
      result.push(tuples2.data[j]);
      j++;
    }

    return Type.list(result);
  },
  // End ukeymerge/3
  // Deps: []

  // Start umerge/1
  "umerge/1": (listOfLists) => {
    if (!Type.isList(listOfLists)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge/1", [listOfLists]),
      );
    }

    if (!Type.isProperList(listOfLists)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge_1/2"),
      );
    }

    if (listOfLists.data.length === 0) {
      return Type.list([]);
    }

    let result = listOfLists.data[0];

    if (!Type.isList(result)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge_1/2"),
      );
    }

    for (let i = 1; i < listOfLists.data.length; i++) {
      result = Erlang_Lists["umerge/2"](result, listOfLists.data[i]);
    }

    return result;
  },
  // End umerge/1
  // Deps: [:lists.umerge/2]

  // Start umerge/2
  "umerge/2": (list1, list2) => {
    if (!Type.isList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge/2", [list1, list2]),
      );
    }

    if (!Type.isList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge/2", [list1, list2]),
      );
    }

    if (!Type.isProperList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge_1/3"),
      );
    }

    if (!Type.isProperList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge_1/3"),
      );
    }

    const result = [];
    let i = 0;
    let j = 0;

    while (i < list1.data.length && j < list2.data.length) {
      const comp = Interpreter.compareTerms(list1.data[i], list2.data[j]);

      if (comp < 0) {
        result.push(list1.data[i]);
        i++;
      } else if (comp > 0) {
        result.push(list2.data[j]);
        j++;
      } else {
        result.push(list1.data[i]);
        i++;
        j++;
      }
    }

    while (i < list1.data.length) {
      result.push(list1.data[i]);
      i++;
    }

    while (j < list2.data.length) {
      result.push(list2.data[j]);
      j++;
    }

    return Type.list(result);
  },
  // End umerge/2
  // Deps: []

  // Start umerge3/3
  "umerge3/3": (list1, list2, list3) => {
    if (!Type.isList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge3/3", [list1, list2, list3]),
      );
    }

    if (!Type.isList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge3/3", [list1, list2, list3]),
      );
    }

    if (!Type.isList(list3)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge3/3", [list1, list2, list3]),
      );
    }

    if (!Type.isProperList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge3_1/4"),
      );
    }

    if (!Type.isProperList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge3_1/4"),
      );
    }

    if (!Type.isProperList(list3)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge3_1/4"),
      );
    }

    const merged12 = Erlang_Lists["umerge/2"](list1, list2);
    return Erlang_Lists["umerge/2"](merged12, list3);
  },
  // End umerge3/3
  // Deps: [:lists.umerge/2]

  // Start umerge/3
  "umerge/3": function (fun, list1, list2) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge/3", arguments),
      );
    }

    if (!Type.isList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge/3", arguments),
      );
    }

    if (!Type.isList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge/3", arguments),
      );
    }

    if (!Type.isProperList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge_1/4"),
      );
    }

    if (!Type.isProperList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.umerge_1/4"),
      );
    }

    const result = [];
    let i = 0;
    let j = 0;

    while (i < list1.data.length && j < list2.data.length) {
      const comp = Interpreter.callAnonymousFunction(fun, [
        list1.data[i],
        list2.data[j],
      ]);

      if (!Type.isBoolean(comp)) {
        Interpreter.raiseErlangError(
          Interpreter.buildErlangErrorMsg(
            `{:bad_generator, ${Interpreter.inspect(comp)}}`,
          ),
        );
      }

      if (Type.isTrue(comp)) {
        // list1[i] < list2[j]
        result.push(list1.data[i]);
        i++;
      } else {
        // Check if equal for union behavior
        const isEqual = Interpreter.isStrictlyEqual(list1.data[i], list2.data[j]);
        if (isEqual) {
          result.push(list1.data[i]);
          i++;
          j++;
        } else {
          result.push(list2.data[j]);
          j++;
        }
      }
    }

    while (i < list1.data.length) {
      result.push(list1.data[i]);
      i++;
    }

    while (j < list2.data.length) {
      result.push(list2.data[j]);
      j++;
    }

    return Type.list(result);
  },
  // End umerge/3
  // Deps: []

  // Start usort/1
  "usort/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.usort/1", [list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.usort_1/4"),
      );
    }

    const sorted = list.data.sort(Interpreter.compareTerms);

    // Remove duplicates
    const unique = [];
    for (let i = 0; i < sorted.length; i++) {
      if (i === 0 || !Interpreter.isStrictlyEqual(sorted[i], sorted[i - 1])) {
        unique.push(sorted[i]);
      }
    }

    return Type.list(unique);
  },
  // End usort/1
  // Deps: []

  // Start usort/2
  "usort/2": function (fun, list) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.usort/2", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.usort/2", arguments),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.usort_2/4"),
      );
    }

    // Sort using custom comparator
    const sorted = [...list.data].sort((a, b) => {
      const result = Interpreter.callAnonymousFunction(fun, [a, b]);

      if (!Type.isBoolean(result)) {
        Interpreter.raiseErlangError(
          Interpreter.buildErlangErrorMsg(
            `{:bad_generator, ${Interpreter.inspect(result)}}`,
          ),
        );
      }

      // If fun returns true, a should come before b (keep order)
      // If fun returns false, b should come before a (swap)
      return Type.isTrue(result) ? -1 : 1;
    });

    // Remove duplicates - only keep first of equal elements
    const unique = [];
    for (let i = 0; i < sorted.length; i++) {
      if (i === 0 || !Interpreter.isStrictlyEqual(sorted[i], sorted[i - 1])) {
        unique.push(sorted[i]);
      }
    }

    return Type.list(unique);
  },
  // End usort/2
  // Deps: []

  // Start zip/2
  "zip/2": (list1, list2) => {
    if (!Type.isList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip/2", [list1, list2]),
      );
    }

    if (!Type.isList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip/2", [list1, list2]),
      );
    }

    if (!Type.isProperList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip_1/3"),
      );
    }

    if (!Type.isProperList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip_1/3"),
      );
    }

    if (list1.data.length !== list2.data.length) {
      Interpreter.raiseErlangError(
        Interpreter.buildErlangErrorMsg(":lists_not_same_length"),
      );
    }

    const result = [];
    for (let i = 0; i < list1.data.length; i++) {
      result.push(Type.tuple([list1.data[i], list2.data[i]]));
    }

    return Type.list(result);
  },
  // End zip/2
  // Deps: []

  // Start zip/3
  "zip/3": (list1, list2, how) => {
    if (!Type.isList(list1) || !Type.isList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip/3", [
          list1,
          list2,
          how,
        ]),
      );
    }

    if (!Type.isProperList(list1) || !Type.isProperList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip_1/3"),
      );
    }

    const len1 = list1.data.length;
    const len2 = list2.data.length;
    const minLen = Math.min(len1, len2);

    // Determine how to handle unequal lengths
    let resultLen = minLen;
    let pad1 = null;
    let pad2 = null;

    if (Type.isAtom(how)) {
      if (how.value === "trim") {
        resultLen = minLen;
      } else if (how.value === "fail") {
        if (len1 !== len2) {
          Interpreter.raiseErlangError(
            Interpreter.buildErlangErrorMsg(":lists_not_same_length"),
          );
        }
        resultLen = len1;
      } else {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.zip/3", [
            list1,
            list2,
            how,
          ]),
        );
      }
    } else if (Type.isTuple(how) && how.data.length === 2) {
      if (Type.isAtom(how.data[0]) && how.data[0].value === "pad") {
        const defaults = how.data[1];
        if (!Type.isTuple(defaults) || defaults.data.length !== 2) {
          Interpreter.raiseFunctionClauseError(
            Interpreter.buildFunctionClauseErrorMsg(":lists.zip/3", [
              list1,
              list2,
              how,
            ]),
          );
        }
        pad1 = defaults.data[0];
        pad2 = defaults.data[1];
        resultLen = Math.max(len1, len2);
      } else {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.zip/3", [
            list1,
            list2,
            how,
          ]),
        );
      }
    } else {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip/3", [
          list1,
          list2,
          how,
        ]),
      );
    }

    const result = [];
    for (let i = 0; i < resultLen; i++) {
      const elem1 = i < len1 ? list1.data[i] : pad1;
      const elem2 = i < len2 ? list2.data[i] : pad2;
      result.push(Type.tuple([elem1, elem2]));
    }

    return Type.list(result);
  },
  // End zip/3
  // Deps: []

  // Start zip3/3
  "zip3/3": (list1, list2, list3) => {
    if (!Type.isList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip3/3", [
          list1,
          list2,
          list3,
        ]),
      );
    }

    if (!Type.isList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip3/3", [
          list1,
          list2,
          list3,
        ]),
      );
    }

    if (!Type.isList(list3)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip3/3", [
          list1,
          list2,
          list3,
        ]),
      );
    }

    if (!Type.isProperList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip3_1/4"),
      );
    }

    if (!Type.isProperList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip3_1/4"),
      );
    }

    if (!Type.isProperList(list3)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip3_1/4"),
      );
    }

    if (
      list1.data.length !== list2.data.length ||
      list1.data.length !== list3.data.length
    ) {
      Interpreter.raiseErlangError(
        Interpreter.buildErlangErrorMsg(":lists_not_same_length"),
      );
    }

    const result = [];
    for (let i = 0; i < list1.data.length; i++) {
      result.push(
        Type.tuple([list1.data[i], list2.data[i], list3.data[i]]),
      );
    }

    return Type.list(result);
  },
  // End zip3/3
  // Deps: []

  // Start zip3/4
  "zip3/4": (list1, list2, list3, how) => {
    if (!Type.isList(list1) || !Type.isList(list2) || !Type.isList(list3)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip3/4", [
          list1,
          list2,
          list3,
          how,
        ]),
      );
    }

    if (
      !Type.isProperList(list1) ||
      !Type.isProperList(list2) ||
      !Type.isProperList(list3)
    ) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip3_1/4"),
      );
    }

    const len1 = list1.data.length;
    const len2 = list2.data.length;
    const len3 = list3.data.length;
    const minLen = Math.min(len1, len2, len3);

    let resultLen = minLen;
    let pad1 = null;
    let pad2 = null;
    let pad3 = null;

    if (Type.isAtom(how)) {
      if (how.value === "trim") {
        resultLen = minLen;
      } else if (how.value === "fail") {
        if (len1 !== len2 || len2 !== len3) {
          Interpreter.raiseErlangError(
            Interpreter.buildErlangErrorMsg(":lists_not_same_length"),
          );
        }
        resultLen = len1;
      } else {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.zip3/4", [
            list1,
            list2,
            list3,
            how,
          ]),
        );
      }
    } else if (Type.isTuple(how) && how.data.length === 2) {
      if (Type.isAtom(how.data[0]) && how.data[0].value === "pad") {
        const defaults = how.data[1];
        if (!Type.isTuple(defaults) || defaults.data.length !== 3) {
          Interpreter.raiseFunctionClauseError(
            Interpreter.buildFunctionClauseErrorMsg(":lists.zip3/4", [
              list1,
              list2,
              list3,
              how,
            ]),
          );
        }
        pad1 = defaults.data[0];
        pad2 = defaults.data[1];
        pad3 = defaults.data[2];
        resultLen = Math.max(len1, len2, len3);
      } else {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.zip3/4", [
            list1,
            list2,
            list3,
            how,
          ]),
        );
      }
    } else {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zip3/4", [
          list1,
          list2,
          list3,
          how,
        ]),
      );
    }

    const result = [];
    for (let i = 0; i < resultLen; i++) {
      const elem1 = i < len1 ? list1.data[i] : pad1;
      const elem2 = i < len2 ? list2.data[i] : pad2;
      const elem3 = i < len3 ? list3.data[i] : pad3;
      result.push(Type.tuple([elem1, elem2, elem3]));
    }

    return Type.list(result);
  },
  // End zip3/4
  // Deps: []

  // Start zipwith/3
  "zipwith/3": function (fun, list1, list2) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith/3", arguments),
      );
    }

    if (!Type.isList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith/3", [
          fun,
          list1,
          list2,
        ]),
      );
    }

    if (!Type.isList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith/3", [
          fun,
          list1,
          list2,
        ]),
      );
    }

    if (!Type.isProperList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith_1/4"),
      );
    }

    if (!Type.isProperList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith_1/4"),
      );
    }

    if (list1.data.length !== list2.data.length) {
      Interpreter.raiseErlangError(
        Interpreter.buildErlangErrorMsg(":lists_not_same_length"),
      );
    }

    const result = [];
    for (let i = 0; i < list1.data.length; i++) {
      const value = Interpreter.callAnonymousFunction(fun, [
        list1.data[i],
        list2.data[i],
      ]);
      result.push(value);
    }

    return Type.list(result);
  },
  // End zipwith/3
  // Deps: []

  // Start zipwith/4
  "zipwith/4": function (fun, list1, list2, how) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith/4", arguments),
      );
    }

    if (!Type.isList(list1) || !Type.isList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith/4", arguments),
      );
    }

    if (!Type.isProperList(list1) || !Type.isProperList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith_1/4"),
      );
    }

    const len1 = list1.data.length;
    const len2 = list2.data.length;
    const minLen = Math.min(len1, len2);

    let resultLen = minLen;
    let pad1 = null;
    let pad2 = null;

    if (Type.isAtom(how)) {
      if (how.value === "trim") {
        resultLen = minLen;
      } else if (how.value === "fail") {
        if (len1 !== len2) {
          Interpreter.raiseErlangError(
            Interpreter.buildErlangErrorMsg(":lists_not_same_length"),
          );
        }
        resultLen = len1;
      } else {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith/4", arguments),
        );
      }
    } else if (Type.isTuple(how) && how.data.length === 2) {
      if (Type.isAtom(how.data[0]) && how.data[0].value === "pad") {
        const defaults = how.data[1];
        if (!Type.isTuple(defaults) || defaults.data.length !== 2) {
          Interpreter.raiseFunctionClauseError(
            Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith/4", arguments),
          );
        }
        pad1 = defaults.data[0];
        pad2 = defaults.data[1];
        resultLen = Math.max(len1, len2);
      } else {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith/4", arguments),
        );
      }
    } else {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith/4", arguments),
      );
    }

    const result = [];
    for (let i = 0; i < resultLen; i++) {
      const elem1 = i < len1 ? list1.data[i] : pad1;
      const elem2 = i < len2 ? list2.data[i] : pad2;
      const value = Interpreter.callAnonymousFunction(fun, [elem1, elem2]);
      result.push(value);
    }

    return Type.list(result);
  },
  // End zipwith/4
  // Deps: []

  // Start zipwith3/4
  "zipwith3/4": function (fun, list1, list2, list3) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 3) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith3/4", arguments),
      );
    }

    if (!Type.isList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith3/4", [
          fun,
          list1,
          list2,
          list3,
        ]),
      );
    }

    if (!Type.isList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith3/4", [
          fun,
          list1,
          list2,
          list3,
        ]),
      );
    }

    if (!Type.isList(list3)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith3/4", [
          fun,
          list1,
          list2,
          list3,
        ]),
      );
    }

    if (!Type.isProperList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith3_1/5"),
      );
    }

    if (!Type.isProperList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith3_1/5"),
      );
    }

    if (!Type.isProperList(list3)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith3_1/5"),
      );
    }

    if (
      list1.data.length !== list2.data.length ||
      list1.data.length !== list3.data.length
    ) {
      Interpreter.raiseErlangError(
        Interpreter.buildErlangErrorMsg(":lists_not_same_length"),
      );
    }

    const result = [];
    for (let i = 0; i < list1.data.length; i++) {
      const value = Interpreter.callAnonymousFunction(fun, [
        list1.data[i],
        list2.data[i],
        list3.data[i],
      ]);
      result.push(value);
    }

    return Type.list(result);
  },
  // End zipwith3/4
  // Deps: []

  // Start zipwith3/5
  "zipwith3/5": function (fun, list1, list2, list3, how) {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 3) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith3/5", arguments),
      );
    }

    if (!Type.isList(list1) || !Type.isList(list2) || !Type.isList(list3)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith3/5", arguments),
      );
    }

    if (
      !Type.isProperList(list1) ||
      !Type.isProperList(list2) ||
      !Type.isProperList(list3)
    ) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith3_1/5"),
      );
    }

    const len1 = list1.data.length;
    const len2 = list2.data.length;
    const len3 = list3.data.length;
    const minLen = Math.min(len1, len2, len3);

    let resultLen = minLen;
    let pad1 = null;
    let pad2 = null;
    let pad3 = null;

    if (Type.isAtom(how)) {
      if (how.value === "trim") {
        resultLen = minLen;
      } else if (how.value === "fail") {
        if (len1 !== len2 || len2 !== len3) {
          Interpreter.raiseErlangError(
            Interpreter.buildErlangErrorMsg(":lists_not_same_length"),
          );
        }
        resultLen = len1;
      } else {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith3/5", arguments),
        );
      }
    } else if (Type.isTuple(how) && how.data.length === 2) {
      if (Type.isAtom(how.data[0]) && how.data[0].value === "pad") {
        const defaults = how.data[1];
        if (!Type.isTuple(defaults) || defaults.data.length !== 3) {
          Interpreter.raiseFunctionClauseError(
            Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith3/5", arguments),
          );
        }
        pad1 = defaults.data[0];
        pad2 = defaults.data[1];
        pad3 = defaults.data[2];
        resultLen = Math.max(len1, len2, len3);
      } else {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith3/5", arguments),
        );
      }
    } else {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.zipwith3/5", arguments),
      );
    }

    const result = [];
    for (let i = 0; i < resultLen; i++) {
      const elem1 = i < len1 ? list1.data[i] : pad1;
      const elem2 = i < len2 ? list2.data[i] : pad2;
      const elem3 = i < len3 ? list3.data[i] : pad3;
      const value = Interpreter.callAnonymousFunction(fun, [elem1, elem2, elem3]);
      result.push(value);
    }

    return Type.list(result);
  },
  // End zipwith3/5
  // Deps: []
};

export default Erlang_Lists;
