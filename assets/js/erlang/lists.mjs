"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Lists = {
  // Start all/2
  "all/2": function (predicate, list) {
    if (!Type.isAnonymousFunction(predicate) || predicate.arity !== 1) {
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
        Interpreter.buildFunctionClauseErrorMsg(":lists.all/2", arguments),
      );
    }

    for (const elem of list.data) {
      const result = Interpreter.callAnonymousFunction(predicate, [elem]);
      if (!Type.isTrue(result)) {
        return Type.boolean(false);
      }
    }

    return Type.boolean(true);
  },
  // End all/2
  // Deps: []

  // Start any/2
  "any/2": function (predicate, list) {
    if (!Type.isAnonymousFunction(predicate) || predicate.arity !== 1) {
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
        Interpreter.buildFunctionClauseErrorMsg(":lists.any/2", arguments),
      );
    }

    for (const elem of list.data) {
      const result = Interpreter.callAnonymousFunction(predicate, [elem]);
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
        Interpreter.buildFunctionClauseErrorMsg(":lists.append/1", [listOfLists]),
      );
    }

    if (!Type.isProperList(listOfLists)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.append/1", [listOfLists]),
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

  // Start concat/1
  "concat/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.concat/1", [list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.concat/1", [list]),
      );
    }

    const parts = [];
    for (const elem of list.data) {
      if (Type.isAtom(elem)) {
        parts.push(elem.value);
      } else if (Type.isInteger(elem)) {
        parts.push(elem.value.toString());
      } else if (Type.isFloat(elem)) {
        parts.push(elem.value.toString());
      } else if (Type.isBinary(elem)) {
        parts.push(elem.text || "");
      } else {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.concat_1/2"),
        );
      }
    }

    return Type.atom(parts.join(""));
  },
  // End concat/1
  // Deps: []

  // Start delete/2
  "delete/2": (elem, list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.delete/2", [elem, list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.delete/2", [elem, list]),
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
    if (!Type.isList(list) || list.data.length === 0) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.droplast/1", [list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.droplast/1", [list]),
      );
    }

    return Type.list(list.data.slice(0, -1));
  },
  // End droplast/1
  // Deps: []

  // Start dropwhile/2
  "dropwhile/2": function (predicate, list) {
    if (!Type.isAnonymousFunction(predicate) || predicate.arity !== 1) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.dropwhile/2", arguments),
      );
    }

    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.dropwhile/2", arguments),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.dropwhile/2", arguments),
      );
    }

    let dropIndex = 0;
    for (let i = 0; i < list.data.length; i++) {
      const result = Interpreter.callAnonymousFunction(predicate, [list.data[i]]);
      if (!Type.isTrue(result)) {
        break;
      }
      dropIndex = i + 1;
    }

    return Type.list(list.data.slice(dropIndex));
  },
  // End dropwhile/2
  // Deps: []

  // Start duplicate/2
  "duplicate/2": (count, elem) => {
    if (!Type.isInteger(count)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.duplicate/2", [count, elem]),
      );
    }

    if (count.value < 0) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.duplicate/2", [count, elem]),
      );
    }

    const n = Number(count.value);
    return Type.list(new Array(n).fill(elem));
  },
  // End duplicate/2
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
        Interpreter.buildFunctionClauseErrorMsg(":lists.filtermap/2", arguments),
      );
    }

    const result = [];
    for (const elem of list.data) {
      const funResult = Interpreter.callAnonymousFunction(fun, [elem]);

      if (Type.isTrue(funResult)) {
        result.push(elem);
      } else if (Type.isTuple(funResult) && funResult.data.length === 2) {
        if (Type.isAtom(funResult.data[0]) && funResult.data[0].value === "true") {
          result.push(funResult.data[1]);
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
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatmap/2", arguments),
      );
    }

    const result = [];
    for (const elem of list.data) {
      const mapped = Interpreter.callAnonymousFunction(fun, [elem]);
      if (!Type.isList(mapped)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.flatmap_1/3"),
        );
      }
      if (!Type.isProperList(mapped)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.flatmap_1/3"),
        );
      }
      result.push(...mapped.data);
    }

    return Type.list(result);
  },
  // End flatmap/2
  // Deps: []

  // Start flatten/2
  "flatten/2": (list, tail) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatten/2", [list, tail]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.flatten/2", [list, tail]),
      );
    }

    const flattened = Erlang_Lists["flatten/1"](list);
    const data = flattened.data.concat(Type.isList(tail) ? tail.data : [tail]);

    return Type.isProperList(tail) ? Type.list(data) : Type.improperList(data);
  },
  // End flatten/2
  // Deps: [:lists.flatten/1]

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
        Interpreter.buildFunctionClauseErrorMsg(":lists.foreach/2", arguments),
      );
    }

    for (const elem of list.data) {
      Interpreter.callAnonymousFunction(fun, [elem]);
    }

    return Type.atom("ok");
  },
  // End foreach/2
  // Deps: []

  // Start join/2
  "join/2": (separator, list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.join/2", [separator, list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.join/2", [separator, list]),
      );
    }

    if (list.data.length === 0) {
      return Type.list([]);
    }

    const result = [list.data[0]];
    for (let i = 1; i < list.data.length; i++) {
      result.push(separator);
      result.push(list.data[i]);
    }

    return Type.list(result);
  },
  // End join/2
  // Deps: []

  // Start last/1
  "last/1": (list) => {
    if (!Type.isList(list) || list.data.length === 0) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.last/1", [list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.last/1", [list]),
      );
    }

    return list.data[list.data.length - 1];
  },
  // End last/1
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

    const index = Number(n.value) - 1;
    if (index < 0 || index >= list.data.length) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.nth/2", [n, list]),
      );
    }

    return list.data[index];
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

    const count = Number(n.value);
    if (count < 0 || count > list.data.length) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.nthtail/2", [n, list]),
      );
    }

    if (count === list.data.length) {
      return Type.isProperList(list) ? Type.list([]) : list.data[list.data.length - 1];
    }

    const data = list.data.slice(count);
    return Type.isProperList(list) ? Type.list(data) : Type.improperList(data);
  },
  // End nthtail/2
  // Deps: []

  // Start partition/2
  "partition/2": function (predicate, list) {
    if (!Type.isAnonymousFunction(predicate) || predicate.arity !== 1) {
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
        Interpreter.buildFunctionClauseErrorMsg(":lists.partition/2", arguments),
      );
    }

    const satisfying = [];
    const notSatisfying = [];

    for (const elem of list.data) {
      const result = Interpreter.callAnonymousFunction(predicate, [elem]);
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

    const start = Number(from.value);
    const end = Number(to.value);

    if (start > end) {
      return Type.list([]);
    }

    const result = [];
    for (let i = start; i <= end; i++) {
      result.push(Type.integer(i));
    }

    return Type.list(result);
  },
  // End seq/2
  // Deps: []

  // Start seq/3
  "seq/3": (from, to, step) => {
    if (!Type.isInteger(from)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.seq/3", [from, to, step]),
      );
    }

    if (!Type.isInteger(to)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.seq/3", [from, to, step]),
      );
    }

    if (!Type.isInteger(step)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.seq/3", [from, to, step]),
      );
    }

    const start = Number(from.value);
    const end = Number(to.value);
    const increment = Number(step.value);

    if (increment === 0) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.seq/3", [from, to, step]),
      );
    }

    if ((increment > 0 && start > end) || (increment < 0 && start < end)) {
      return Type.list([]);
    }

    const result = [];
    if (increment > 0) {
      for (let i = start; i <= end; i += increment) {
        result.push(Type.integer(i));
      }
    } else {
      for (let i = start; i >= end; i += increment) {
        result.push(Type.integer(i));
      }
    }

    return Type.list(result);
  },
  // End seq/3
  // Deps: []

  // Start keydelete/3
  "keydelete/3": (key, n, tupleList) => {
    if (!Type.isInteger(n)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (n.value < 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    }

    if (!Type.isList(tupleList)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    if (!Type.isProperList(tupleList)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a proper list"),
      );
    }

    const result = [];
    let deleted = false;

    for (const tuple of tupleList.data) {
      if (
        !deleted &&
        Type.isTuple(tuple) &&
        tuple.data.length >= n.value &&
        Interpreter.isStrictlyEqual(tuple.data[Number(n.value) - 1], key)
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

  // Start keyreplace/4
  "keyreplace/4": (key, n, tupleList, newTuple) => {
    if (!Type.isInteger(n)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (n.value < 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    }

    if (!Type.isList(tupleList)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    if (!Type.isProperList(tupleList)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a proper list"),
      );
    }

    const result = [];
    let replaced = false;

    for (const tuple of tupleList.data) {
      if (
        !replaced &&
        Type.isTuple(tuple) &&
        tuple.data.length >= n.value &&
        Interpreter.isStrictlyEqual(tuple.data[Number(n.value) - 1], key)
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
  "keysort/2": (n, tupleList) => {
    if (!Type.isInteger(n)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (n.value < 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    }

    if (!Type.isList(tupleList)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.keysort/2", [n, tupleList]),
      );
    }

    if (!Type.isProperList(tupleList)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.keysort/2", [n, tupleList]),
      );
    }

    const index = Number(n.value) - 1;

    // Validate all elements are tuples with sufficient size
    for (const tuple of tupleList.data) {
      if (!Type.isTuple(tuple)) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(2, "list element is not a tuple"),
        );
      }
      if (tuple.data.length < n.value) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(2, "tuple size is too small"),
        );
      }
    }

    const sorted = tupleList.data.slice().sort((a, b) => {
      return Interpreter.compareTerms(a.data[index], b.data[index]);
    });

    return Type.list(sorted);
  },
  // End keysort/2
  // Deps: []

  // Start keystore/4
  "keystore/4": (key, n, tupleList, newTuple) => {
    if (!Type.isInteger(n)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (n.value < 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    }

    if (!Type.isList(tupleList)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    if (!Type.isProperList(tupleList)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a proper list"),
      );
    }

    const result = [];
    let stored = false;

    for (const tuple of tupleList.data) {
      if (
        !stored &&
        Type.isTuple(tuple) &&
        tuple.data.length >= n.value &&
        Interpreter.isStrictlyEqual(tuple.data[Number(n.value) - 1], key)
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

  // Start keytake/3
  "keytake/3": (key, n, tupleList) => {
    if (!Type.isInteger(n)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (n.value < 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    }

    if (!Type.isList(tupleList)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    if (!Type.isProperList(tupleList)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a proper list"),
      );
    }

    const result = [];
    let foundTuple = null;

    for (const tuple of tupleList.data) {
      if (
        foundTuple === null &&
        Type.isTuple(tuple) &&
        tuple.data.length >= n.value &&
        Interpreter.isStrictlyEqual(tuple.data[Number(n.value) - 1], key)
      ) {
        foundTuple = tuple;
      } else {
        result.push(tuple);
      }
    }

    if (foundTuple !== null) {
      return Type.tuple([
        Type.atom("value"),
        foundTuple,
        Type.list(result),
      ]);
    } else {
      return Type.boolean(false);
    }
  },
  // End keytake/3
  // Deps: []

  // Start mapfoldl/3
  "mapfoldl/3": function (fun, acc0, list) {
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
        Interpreter.buildFunctionClauseErrorMsg(":lists.mapfoldl/3", arguments),
      );
    }

    const result = [];
    let acc = acc0;

    for (const elem of list.data) {
      const funResult = Interpreter.callAnonymousFunction(fun, [elem, acc]);

      if (!Type.isTuple(funResult) || funResult.data.length !== 2) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.mapfoldl_1/3"),
        );
      }

      result.push(funResult.data[0]);
      acc = funResult.data[1];
    }

    return Type.tuple([Type.list(result), acc]);
  },
  // End mapfoldl/3
  // Deps: []

  // Start max/1
  "max/1": (list) => {
    if (!Type.isList(list) || list.data.length === 0) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.max/1", [list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.max/1", [list]),
      );
    }

    let maxElem = list.data[0];
    for (let i = 1; i < list.data.length; i++) {
      if (Interpreter.compareTerms(list.data[i], maxElem) === 1) {
        maxElem = list.data[i];
      }
    }

    return maxElem;
  },
  // End max/1
  // Deps: []

  // Start min/1
  "min/1": (list) => {
    if (!Type.isList(list) || list.data.length === 0) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.min/1", [list]),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.min/1", [list]),
      );
    }

    let minElem = list.data[0];
    for (let i = 1; i < list.data.length; i++) {
      if (Interpreter.compareTerms(list.data[i], minElem) === -1) {
        minElem = list.data[i];
      }
    }

    return minElem;
  },
  // End min/1
  // Deps: []

  // Start prefix/2
  "prefix/2": (list1, list2) => {
    if (!Type.isList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.prefix/2", [list1, list2]),
      );
    }

    if (!Type.isProperList(list1)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.prefix/2", [list1, list2]),
      );
    }

    if (!Type.isList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.prefix/2", [list1, list2]),
      );
    }

    if (!Type.isProperList(list2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":lists.prefix/2", [list1, list2]),
      );
    }

    if (list1.data.length > list2.data.length) {
      return Type.boolean(false);
    }

    for (let i = 0; i < list1.data.length; i++) {
      if (!Interpreter.isStrictlyEqual(list1.data[i], list2.data[i])) {
        return Type.boolean(false);
      }
    }

    return Type.boolean(true);
  },
  // End prefix/2
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
        Interpreter.buildFunctionClauseErrorMsg(":lists.sort/2", arguments),
      );
    }

    const sorted = list.data.slice().sort((a, b) => {
      const result = Interpreter.callAnonymousFunction(fun, [a, b]);

      if (!Type.isBoolean(result)) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":lists.sort_1/3"),
        );
      }

      return Type.isTrue(result) ? -1 : 0;
    });

    return Type.list(sorted);
  },
  // End sort/2
  // Deps: []
};

export default Erlang_Lists;
