"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Elixir_Enum = {
  // Start at/2
  "at/2": (enumerable, index) => {
    return Elixir_Enum["at/3"](enumerable, index, Type.atom("nil"));
  },
  // End at/2
  // Deps: [Enum.at/3]

  // Start at/3
  "at/3": (enumerable, index, defaultValue) => {
    if (!Type.isList(enumerable)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isInteger(index)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    const indexNum = Number(index.value);
    const list = enumerable.data;

    // Negative indices count from the end
    const actualIndex = indexNum < 0 ? list.length + indexNum : indexNum;

    if (actualIndex < 0 || actualIndex >= list.length) {
      return defaultValue;
    }

    return list[actualIndex];
  },
  // End at/3
  // Deps: []

  // Start concat/1
  "concat/1": (enumerables) => {
    if (!Type.isList(enumerables)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    const result = [];

    for (const enumerable of enumerables.data) {
      if (!Type.isList(enumerable)) {
        Interpreter.raiseArgumentError("argument error");
      }
      result.push(...enumerable.data);
    }

    return Type.list(result);
  },
  // End concat/1
  // Deps: []

  // Start concat/2
  "concat/2": (left, right) => {
    if (!Type.isList(left)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isList(right)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    return Type.list([...left.data, ...right.data]);
  },
  // End concat/2
  // Deps: []

  // Start count/1
  "count/1": (enumerable) => {
    if (!Type.isList(enumerable)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    return Type.integer(enumerable.data.length);
  },
  // End count/1
  // Deps: []

  // Start count/2
  "count/2": (enumerable, fun) => {
    if (!Type.isList(enumerable)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isAnonymousFunction(fun) || fun.arity !== 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          2,
          "not a fun that takes one argument",
        ),
      );
    }

    let count = 0;

    for (const elem of enumerable.data) {
      const result = Interpreter.callAnonymousFunction(fun, [elem]);
      if (!Type.isFalse(result) && !Type.isNil(result)) {
        count++;
      }
    }

    return Type.integer(count);
  },
  // End count/2
  // Deps: []

  // Start empty?/1
  "empty?/1": (enumerable) => {
    if (!Type.isList(enumerable)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    return Type.boolean(enumerable.data.length === 0);
  },
  // End empty?/1
  // Deps: []

  // Start member?/2
  "member?/2": (enumerable, element) => {
    if (!Type.isList(enumerable)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    for (const elem of enumerable.data) {
      if (Interpreter.compareTerms(elem, element) === 0) {
        return Type.boolean(true);
      }
    }

    return Type.boolean(false);
  },
  // End member?/2
  // Deps: []

  // Start reverse/1
  "reverse/1": (enumerable) => {
    if (!Type.isList(enumerable)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    return Type.list([...enumerable.data].reverse());
  },
  // End reverse/1
  // Deps: []

  // Start take/2
  "take/2": (enumerable, amount) => {
    if (!Type.isList(enumerable)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isInteger(amount)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    const amountNum = Number(amount.value);

    if (amountNum >= 0) {
      return Type.list(enumerable.data.slice(0, amountNum));
    } else {
      // Negative amount takes from the end
      return Type.list(enumerable.data.slice(amountNum));
    }
  },
  // End take/2
  // Deps: []

  // Start drop/2
  "drop/2": (enumerable, amount) => {
    if (!Type.isList(enumerable)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isInteger(amount)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    const amountNum = Number(amount.value);

    if (amountNum >= 0) {
      return Type.list(enumerable.data.slice(amountNum));
    } else {
      // Negative amount drops from the end
      return Type.list(enumerable.data.slice(0, amountNum));
    }
  },
  // End drop/2
  // Deps: []
};

export default Elixir_Enum;
