"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Lists = {
  // Mirrors the server's private do_flatten/2, threading the flattened
  // continuation through the recursion the way the Erlang clauses do: nested
  // lists are flattened innermost-first from the right, so the rightmost
  // improper cell fails first, with the continuation built so far as the
  // second arg.
  // Start _do_flatten/2
  "_do_flatten/2": (term, tail) => {
    if (!Type.isList(term)) {
      Interpreter.raiseFunctionClauseError("lists", "do_flatten", 2, [
        term,
        tail,
      ]);
    }

    if (!term.isProper) {
      Interpreter.raiseFunctionClauseError("lists", "do_flatten", 2, [
        term.data.at(-1),
        tail,
      ]);
    }

    let result = tail;

    for (let i = term.data.length - 1; i >= 0; i--) {
      const elem = term.data[i];

      if (Type.isList(elem)) {
        result = Erlang_Lists["_do_flatten/2"](elem, result);
      } else {
        result = result.isProper
          ? Type.list([elem, ...result.data])
          : Type.improperList([elem, ...result.data]);
      }
    }

    return result;
  },
  // End _do_flatten/2
  // Deps: []

  // Start all/2
  "all/2": (fun, list) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError("lists", "all", 2, [fun, list]);
    }

    if (!Type.isList(list)) {
      Interpreter.raiseCaseClauseError(list);
    }

    const properLength = list.isProper
      ? list.data.length
      : list.data.length - 1;

    for (let i = 0; i < properLength; i++) {
      const res = Interpreter.callAnonymousFunction(fun, [list.data[i]]);

      if (!Type.isTrue(res)) {
        return Type.boolean(false);
      }
    }

    if (!list.isProper) {
      Interpreter.raiseFunctionClauseError("lists", "all_1", 2, [
        fun,
        list.data.at(-1),
      ]);
    }

    return Type.boolean(true);
  },
  // End all/2
  // Deps: []

  // Start any/2
  "any/2": (fun, list) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError("lists", "any", 2, [fun, list]);
    }

    if (!Type.isList(list)) {
      Interpreter.raiseCaseClauseError(list);
    }

    const properLength = list.isProper
      ? list.data.length
      : list.data.length - 1;

    for (let i = 0; i < properLength; i++) {
      const res = Interpreter.callAnonymousFunction(fun, [list.data[i]]);

      if (Type.isTrue(res)) {
        return Type.boolean(true);
      }
    }

    if (!list.isProper) {
      Interpreter.raiseFunctionClauseError("lists", "any_1", 2, [
        fun,
        list.data.at(-1),
      ]);
    }

    return Type.boolean(false);
  },
  // End any/2
  // Deps: []

  // Start duplicate/2
  "duplicate/2": (n, elem) => {
    if (!Type.isInteger(n) || n.value < 0n) {
      Interpreter.raiseFunctionClauseError("lists", "duplicate", 2, [n, elem]);
    }

    const count = Number(n.value);
    const result = new Array(count);

    for (let i = 0; i < count; i++) {
      result[i] = elem;
    }

    return Type.list(result);
  },
  // End duplicate/2
  // Deps: []

  // Start filter/2
  "filter/2": (fun, list) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError("lists", "filter", 2, [fun, list]);
    }

    if (!Type.isList(list)) {
      Erlang["error/1"](Type.tuple([Type.atom("bad_generator"), list]));
    }

    if (!Type.isProperList(list)) {
      Erlang["error/1"](
        Type.tuple([Type.atom("bad_generator"), list.data.at(-1)]),
      );
    }

    return Type.list(
      list.data.filter((elem) => {
        const result = Interpreter.callAnonymousFunction(fun, [elem]);

        if (!Type.isBoolean(result)) {
          Erlang["error/1"](Type.tuple([Type.atom("bad_filter"), result]));
        }

        return Type.isTrue(result);
      }),
    );
  },
  // End filter/2
  // Deps: [:erlang.error/1]

  // Start flatmap/2
  "flatmap/2": (fun, list) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError("lists", "flatmap", 2, [fun, list]);
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError("lists", "flatmap_1", 2, [
        fun,
        list,
      ]);
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError("lists", "flatmap_1", 2, [
        fun,
        list.data.at(-1),
      ]);
    }

    const mappedResults = list.data.map((elem) =>
      Interpreter.callAnonymousFunction(fun, [elem]),
    );

    // The server concatenates the mapped results back-to-front, so an
    // invalid mapper result fails in the ++ BIF with the flattened suffix
    // already accumulated as the second operand.
    let acc = [];

    for (let i = mappedResults.length - 1; i >= 0; i--) {
      const mapped = mappedResults[i];

      if (!Type.isProperList(mapped)) {
        // TODO: plant the erl_erts_errors error_info once the client carries
        // that format module.
        Interpreter.raiseBifError(
          "badarg",
          "erlang",
          "++",
          [mapped, Type.list(acc)],
          null,
        );
      }

      acc = mapped.data.concat(acc);
    }

    return Type.list(acc);
  },
  // End flatmap/2
  // Deps: []

  // Start flatten/1
  "flatten/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError("lists", "flatten", 1, [list]);
    }

    return Erlang_Lists["_do_flatten/2"](list, Type.list());
  },
  // End flatten/1
  // Deps: [:lists._do_flatten/2]

  // Start flatten/2
  "flatten/2": (list, tail) => {
    if (!Type.isList(list) || !Type.isList(tail)) {
      Interpreter.raiseFunctionClauseError("lists", "flatten", 2, [list, tail]);
    }

    return Erlang_Lists["_do_flatten/2"](list, tail);
  },
  // End flatten/2
  // Deps: [:lists._do_flatten/2]

  // Start foldl/3
  "foldl/3": (fun, initialAcc, list) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseFunctionClauseError("lists", "foldl", 3, [
        fun,
        initialAcc,
        list,
      ]);
    }

    if (!Type.isList(list)) {
      Interpreter.raiseCaseClauseError(list);
    }

    const properLength = list.isProper
      ? list.data.length
      : list.data.length - 1;

    let acc = initialAcc;

    for (let i = 0; i < properLength; i++) {
      acc = Interpreter.callAnonymousFunction(fun, [list.data[i], acc]);
    }

    // The server folds the proper prefix before failing on the tail, so the
    // frame carries the accumulator built so far.
    if (!list.isProper) {
      Interpreter.raiseFunctionClauseError("lists", "foldl_1", 3, [
        fun,
        acc,
        list.data.at(-1),
      ]);
    }

    return acc;
  },
  // End foldl/3
  // Deps: []

  // Start foldr/3
  "foldr/3": (fun, initialAcc, list) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseFunctionClauseError("lists", "foldr", 3, [
        fun,
        initialAcc,
        list,
      ]);
    }

    // The server recurses to the end of the list before folding, so a bad
    // list fails with the initial accumulator and the offending term, and no
    // fun application happens.
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError("lists", "foldr_1", 3, [
        fun,
        initialAcc,
        list,
      ]);
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError("lists", "foldr_1", 3, [
        fun,
        initialAcc,
        list.data.at(-1),
      ]);
    }

    return list.data.reduceRight(
      (acc, elem) => Interpreter.callAnonymousFunction(fun, [elem, acc]),
      initialAcc,
    );
  },
  // End foldr/3
  // Deps: []

  // Start foreach/2
  "foreach/2": (fun, list) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError("lists", "foreach", 2, [fun, list]);
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError("lists", "foreach_1", 2, [
        fun,
        list,
      ]);
    }

    const properLength = list.isProper
      ? list.data.length
      : list.data.length - 1;

    for (let i = 0; i < properLength; i++) {
      Interpreter.callAnonymousFunction(fun, [list.data[i]]);
    }

    // The server applies the fun through the proper prefix before failing
    // on the tail.
    if (!list.isProper) {
      Interpreter.raiseFunctionClauseError("lists", "foreach_1", 2, [
        fun,
        list.data.at(-1),
      ]);
    }

    return Type.atom("ok");
  },
  // End foreach/2
  // Deps: []

  // Start keydelete/3
  "keydelete/3": (key, index, tuples) => {
    if (!Type.isInteger(index) || index.value < 1n) {
      Interpreter.raiseFunctionClauseError("lists", "keydelete", 3, [
        key,
        index,
        tuples,
      ]);
    }

    if (!Type.isProperList(tuples)) {
      const thirdArg = Type.isList(tuples) ? tuples.data.at(-1) : tuples;

      Interpreter.raiseFunctionClauseError("lists", "keydelete3", 3, [
        key,
        index,
        thirdArg,
      ]);
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
    if (
      !Type.isInteger(index) ||
      index.value < 1n ||
      !Type.isProperList(tuples)
    ) {
      Interpreter.raiseBifError("badarg", "lists", "keyfind", [
        value,
        index,
        tuples,
      ]);
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
    let result;

    try {
      result = Erlang_Lists["keyfind/3"](value, index, tuples);
    } catch (error) {
      if (error.struct) {
        // Re-raise with this function's own identity - the BEAM reports the
        // called function's frame, not the delegate's.
        Interpreter.raiseBifError("badarg", "lists", "keymember", [
          value,
          index,
          tuples,
        ]);
      }

      throw error;
    }

    return Type.boolean(Type.isTuple(result));
  },
  // End keymember/3
  // Deps: [:lists.keyfind/3]

  // Start keyreplace/4
  "keyreplace/4": (key, index, tuples, newTuple) => {
    if (!Type.isInteger(index) || index.value < 1n || !Type.isTuple(newTuple)) {
      Interpreter.raiseFunctionClauseError("lists", "keyreplace", 4, [
        key,
        index,
        tuples,
        newTuple,
      ]);
    }

    if (!Type.isProperList(tuples)) {
      const thirdArg = Type.isList(tuples) ? tuples.data.at(-1) : tuples;

      Interpreter.raiseFunctionClauseError("lists", "keyreplace3", 4, [
        key,
        index,
        thirdArg,
        newTuple,
      ]);
    }

    let resultData = tuples.data;

    for (let i = 0; i < tuples.data.length; i++) {
      const tuple = tuples.data[i];

      if (
        Type.isTuple(tuple) &&
        tuple.data.length >= index.value &&
        Interpreter.isEqual(tuple.data[Number(index.value) - 1], key)
      ) {
        resultData = [
          ...tuples.data.slice(0, i),
          newTuple,
          ...tuples.data.slice(i + 1),
        ];
        break;
      }
    }

    return Type.list(resultData);
  },
  // End keyreplace/4
  // Deps: []

  // Start keysort/2
  "keysort/2": (index, tuples) => {
    if (!Type.isInteger(index) || index.value <= 0n) {
      Interpreter.raiseFunctionClauseError("lists", "keysort", 2, [
        index,
        tuples,
      ]);
    }

    if (!Type.isList(tuples)) {
      Interpreter.raiseCaseClauseError(tuples);
    }

    if (Type.isImproperList(tuples)) {
      if (tuples.data.length === 2) {
        Interpreter.raiseCaseClauseError(tuples);
      } else if (tuples.data.every((item) => Type.isTuple(item))) {
        // The server's keysplit frame args carry the sort's in-progress
        // state, which the client doesn't mirror, so the frame carries the
        // bare arity.
        Interpreter.raiseFunctionClauseError("lists", "keysplit_1", 8);
      } else {
        // TODO: raise through the erl_erts_errors error_info once the client
        // carries that format module.
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

  // Start keystore/4
  "keystore/4": (key, index, tuples, newTuple) => {
    if (!Type.isInteger(index) || index.value < 1n || !Type.isTuple(newTuple)) {
      Interpreter.raiseFunctionClauseError("lists", "keystore", 4, [
        key,
        index,
        tuples,
        newTuple,
      ]);
    }

    if (!Type.isProperList(tuples)) {
      const thirdArg = Type.isList(tuples) ? tuples.data.at(-1) : tuples;

      Interpreter.raiseFunctionClauseError("lists", "keystore2", 4, [
        key,
        index,
        thirdArg,
        newTuple,
      ]);
    }

    for (let i = 0; i < tuples.data.length; i++) {
      const tuple = tuples.data[i];

      if (
        Type.isTuple(tuple) &&
        tuple.data.length >= index.value &&
        Interpreter.isEqual(tuple.data[Number(index.value) - 1], key)
      ) {
        const resultData = [
          ...tuples.data.slice(0, i),
          newTuple,
          ...tuples.data.slice(i + 1),
        ];

        return Type.list(resultData);
      }
    }

    return Type.list([...tuples.data, newTuple]);
  },
  // End keystore/4
  // Deps: []

  // Start keytake/3
  "keytake/3": (key, index, tuples) => {
    if (!Type.isInteger(index) || index.value < 1n) {
      Interpreter.raiseFunctionClauseError("lists", "keytake", 3, [
        key,
        index,
        tuples,
      ]);
    }

    if (!Type.isList(tuples)) {
      Interpreter.raiseFunctionClauseError("lists", "keytake", 4, [
        key,
        index,
        tuples,
        Type.list(),
      ]);
    }

    const properLength = tuples.isProper
      ? tuples.data.length
      : tuples.data.length - 1;

    for (let i = 0; i < properLength; i++) {
      const tuple = tuples.data[i];

      if (
        Type.isTuple(tuple) &&
        tuple.data.length >= index.value &&
        Interpreter.isEqual(tuple.data[Number(index.value) - 1], key)
      ) {
        const restData = [
          ...tuples.data.slice(0, i),
          ...tuples.data.slice(i + 1),
        ];

        let rest;

        if (tuples.isProper) {
          rest = Type.list(restData);
        } else {
          rest =
            restData.length === 1 ? restData[0] : Type.improperList(restData);
        }

        return Type.tuple([Type.atom("value"), tuple, rest]);
      }
    }

    // The server accumulates the visited tuples in reverse, so an improper
    // list without a match fails with the tail and that accumulator.
    if (!tuples.isProper) {
      Interpreter.raiseFunctionClauseError("lists", "keytake", 4, [
        key,
        index,
        tuples.data.at(-1),
        Type.list(tuples.data.slice(0, -1).toReversed()),
      ]);
    }

    return Type.boolean(false);
  },
  // End keytake/3
  // Deps: []

  // Start map/2
  "map/2": (fun, list) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseFunctionClauseError("lists", "map", 2, [fun, list]);
    }

    if (!Type.isList(list)) {
      Interpreter.raiseCaseClauseError(list);
    }

    const properLength = list.isProper
      ? list.data.length
      : list.data.length - 1;

    const mapped = [];

    for (let i = 0; i < properLength; i++) {
      mapped.push(Interpreter.callAnonymousFunction(fun, [list.data[i]]));
    }

    // The server maps the proper prefix before failing on the tail.
    if (!list.isProper) {
      Interpreter.raiseFunctionClauseError("lists", "map_1", 2, [
        fun,
        list.data.at(-1),
      ]);
    }

    return Type.list(mapped);
  },
  // End map/2
  // Deps: []

  // Start mapfoldl/3
  "mapfoldl/3": (fun, initialAcc, list) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseFunctionClauseError("lists", "mapfoldl", 3, [
        fun,
        initialAcc,
        list,
      ]);
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError("lists", "mapfoldl_1", 3, [
        fun,
        initialAcc,
        list,
      ]);
    }

    const isProperList = Type.isProperList(list);

    const elementsCount = isProperList
      ? list.data.length
      : Math.max(list.data.length - 1, 0);

    let acc = initialAcc;
    const mappedElements = [];

    for (let i = 0; i < elementsCount; ++i) {
      const result = Interpreter.callAnonymousFunction(fun, [
        list.data[i],
        acc,
      ]);

      if (!Type.isTuple(result) || result.data.length !== 2) {
        Interpreter.raiseMatchError(result);
      }

      mappedElements.push(result.data[0]);
      acc = result.data[1];
    }

    if (!isProperList) {
      Interpreter.raiseFunctionClauseError("lists", "mapfoldl_1", 3, [
        fun,
        acc,
        list.data.at(-1),
      ]);
    }

    return Type.tuple([Type.list(mappedElements), acc]);
  },
  // End mapfoldl/3
  // Deps: []

  // Start max/1
  "max/1": (list) => {
    if (!Type.isList(list) || list.data.length === 0) {
      Interpreter.raiseFunctionClauseError("lists", "max", 1, [list]);
    }

    const properLength = list.isProper
      ? list.data.length
      : list.data.length - 1;

    let max = list.data[0];

    for (let i = 1; i < properLength; i++) {
      if (Interpreter.compareTerms(list.data[i], max) > 0) {
        max = list.data[i];
      }
    }

    // The server threads the running maximum through max/2, so an improper
    // list fails there with the tail and the maximum found so far.
    if (!list.isProper) {
      Interpreter.raiseFunctionClauseError("lists", "max", 2, [
        list.data.at(-1),
        max,
      ]);
    }

    return max;
  },
  // End max/1
  // Deps: []

  // Start member/2
  "member/2": (elem, list) => {
    const raiseBadarg = () => {
      Interpreter.raiseBifError("badarg", "lists", "member", [elem, list]);
    };

    if (!Type.isList(list)) {
      raiseBadarg();
    }

    const isProperList = Type.isProperList(list);

    for (let i = 0; i < list.data.length; ++i) {
      if (Interpreter.isStrictlyEqual(list.data[i], elem)) {
        if (i < list.data.length - 1 || isProperList) {
          return Type.boolean(true);
        } else {
          raiseBadarg();
        }
      }
    }

    if (!isProperList) {
      raiseBadarg();
    }

    return Type.boolean(false);
  },
  // End member/2
  // Deps: []

  // Start min/1
  "min/1": (list) => {
    if (!Type.isList(list) || list.data.length === 0) {
      Interpreter.raiseFunctionClauseError("lists", "min", 1, [list]);
    }

    const properLength = list.isProper
      ? list.data.length
      : list.data.length - 1;

    let min = list.data[0];

    for (let i = 1; i < properLength; i++) {
      if (Interpreter.compareTerms(list.data[i], min) < 0) {
        min = list.data[i];
      }
    }

    // The server threads the running minimum through min/2, so an improper
    // list fails there with the tail and the minimum found so far.
    if (!list.isProper) {
      Interpreter.raiseFunctionClauseError("lists", "min", 2, [
        list.data.at(-1),
        min,
      ]);
    }

    return min;
  },
  // End min/1
  // Deps: []

  // Start prefix/2
  "prefix/2": (list1, list2) => {
    if (!Type.isList(list1) || !Type.isList(list2)) {
      Interpreter.raiseFunctionClauseError("lists", "prefix", 2, [
        list1,
        list2,
      ]);
    }

    const length1 = list1.data.length;
    const length2 = list2.data.length;
    let index = 0;

    const tail = (list) => {
      if (Type.isProperList(list)) {
        return Type.list(list.data.slice(index));
      } else {
        if (list.data.length === index + 1) {
          return list.data.at(-1);
        } else {
          return Type.improperList(list.data.slice(index));
        }
      }
    };

    // Emulate the Erlang implementation to ensure that the same errors are raised when improper lists are involved
    while (true) {
      // The end of an improper list has been reached, raise error
      if (
        (length1 === index + 1 && Type.isImproperList(list1)) ||
        (length2 === index + 1 && Type.isImproperList(list2))
      ) {
        Interpreter.raiseFunctionClauseError("lists", "prefix", 2, [
          tail(list1),
          tail(list2),
        ]);
      } // Next element matches, so the first list could be a prefix of the second list
      else if (
        length1 > index &&
        length2 > index &&
        Interpreter.isStrictlyEqual(list1.data[index], list2.data[index])
      ) {
        index++;
      }
      // Reached the end of the first list, so it is a prefix
      else if (length1 === index) {
        return Type.boolean(true);
      }
      // Otherwise, not a prefix
      else {
        return Type.boolean(false);
      }
    }
  },
  // End prefix/2
  // Deps: []

  // Start reverse/1
  "reverse/1": (list) => {
    // The BEAM matches the first two elements in reverse/1's own clauses, so
    // a non-list or an improper list with fewer than two proper elements
    // fails there, while a longer improper list fails in the reverse/2 BIF
    // with the reversal state accumulated so far.
    if (
      !Type.isList(list) ||
      (!Type.isProperList(list) && list.data.length === 2)
    ) {
      Interpreter.raiseFunctionClauseError("lists", "reverse", 1, [list]);
    }

    if (!Type.isProperList(list)) {
      const rest =
        list.data.length === 3
          ? list.data.at(-1)
          : Type.improperList(list.data.slice(2));

      Interpreter.raiseBifError("badarg", "lists", "reverse", [
        rest,
        Type.list([list.data[1], list.data[0]]),
      ]);
    }

    return Type.list(list.data.toReversed());
  },
  // End reverse/1
  // Deps: []

  // Start reverse/2
  "reverse/2": (list, tail) => {
    if (!Type.isProperList(list)) {
      Interpreter.raiseBifError("badarg", "lists", "reverse", [list, tail]);
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

  // Start seq/2
  "seq/2": (from, to) => {
    if (
      !Type.isInteger(from) ||
      !Type.isInteger(to) ||
      from.value > to.value + 1n
    ) {
      Interpreter.raiseFunctionClauseError("lists", "seq", 2, [from, to]);
    }

    return Erlang_Lists["seq/3"](from, to, Type.integer(1));
  },
  // End seq/2
  // Deps: [:lists.seq/3]

  // Start seq/3
  "seq/3": (fromTerm, toTerm, incrTerm) => {
    const raiseBadarg = () => {
      Interpreter.raiseBifError("badarg", "lists", "seq", [
        fromTerm,
        toTerm,
        incrTerm,
      ]);
    };

    if (
      !Type.isInteger(fromTerm) ||
      !Type.isInteger(toTerm) ||
      !Type.isInteger(incrTerm)
    ) {
      raiseBadarg();
    }

    const from = fromTerm.value;
    const to = toTerm.value;
    const incr = incrTerm.value;

    // Special case: seq(same, same, 0) when is_integer(same) -> [same]
    if (from === to && incr === 0n) {
      return Type.list([Type.integer(from)]);
    }

    // Erlang guard: (incr > 0 andalso from - incr =< to)
    // orelse (incr < 0 andalso from - incr >= to)
    if (!(
      (incr > 0n && from - incr <= to) ||
      (incr < 0n && from - incr >= to)
    )) {
      raiseBadarg();
    }

    const result = [];

    if (incr > 0n) {
      for (let i = from; i <= to; i += incr) {
        result.push(Type.integer(i));
      }
    } else {
      for (let i = from; i >= to; i += incr) {
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
      Interpreter.raiseFunctionClauseError("lists", "sort", 1, [list]);
    }

    if (!Type.isProperList(list)) {
      // Match server behavior for improper lists:
      // - 1 proper element: the sort/1 clause head fails
      // - 2 proper elements: the first comparison picks the split function
      //   that then fails on the tail
      // - longer: the failure happens deep in the split state, which the
      //   client doesn't mirror, so the frame carries the bare arity
      if (list.data.length === 2) {
        Interpreter.raiseFunctionClauseError("lists", "sort", 1, [list]);
      }

      if (list.data.length === 3) {
        const x = list.data[0];
        const y = list.data[1];

        const splitFun =
          Interpreter.compareTerms(x, y) <= 0 ? "split_1" : "split_2";

        Interpreter.raiseFunctionClauseError("lists", splitFun, 5, [
          x,
          y,
          list.data.at(-1),
          Type.list(),
          Type.list(),
        ]);
      }

      Interpreter.raiseFunctionClauseError("lists", "split_1", 5);
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
      Interpreter.raiseBadFunctionError(fun);
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError("lists", "sort", 2, [fun, list]);
    }

    if (!Type.isProperList(list)) {
      // Match server behavior for improper lists:
      // - 1 proper element: the sort/2 clause head fails
      // - 2 proper elements: the first comparison picks the fsplit function
      //   that then fails on the tail
      // - longer: the failure happens deep in the split state, which the
      //   client doesn't mirror, so the frame carries the bare arity
      if (list.data.length <= 2) {
        Interpreter.raiseFunctionClauseError("lists", "sort", 2, [fun, list]);
      }

      if (list.data.length === 3) {
        const x = list.data[0];
        const y = list.data[1];

        const fsplitFun = Type.isTrue(
          Interpreter.callAnonymousFunction(fun, [x, y]),
        )
          ? "fsplit_1"
          : "fsplit_2";

        Interpreter.raiseFunctionClauseError("lists", fsplitFun, 6, [
          y,
          x,
          fun,
          list.data.at(-1),
          Type.list(),
          Type.list(),
        ]);
      }

      Interpreter.raiseFunctionClauseError("lists", "fsplit_1", 6);
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

  // Start suffix/2
  "suffix/2": (list1, list2) => {
    // The Erlang implementation computes length/1 on both arguments, which
    // rejects anything that is not a proper list with an "not a list" error.
    if (!Type.isProperList(list1) || !Type.isProperList(list2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    const length1 = list1.data.length;
    const delta = list2.data.length - length1;

    // The first list cannot be a suffix of a shorter second list.
    if (delta < 0) {
      return Type.boolean(false);
    }

    // Compare the first list against the trailing part of the second list
    // in place, avoiding any intermediate allocation.
    for (let i = 0; i < length1; i++) {
      if (!Interpreter.isStrictlyEqual(list1.data[i], list2.data[delta + i])) {
        return Type.boolean(false);
      }
    }

    return Type.boolean(true);
  },
  // End suffix/2
  // Deps: []
};

export default Erlang_Lists;
