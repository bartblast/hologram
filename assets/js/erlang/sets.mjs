"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// Erlang sets are represented as {set, Version, Elements}
// where Elements is an array of unique elements

function isSet(term) {
  if (!Type.isTuple(term) || term.data.length < 3) {
    return false;
  }

  const marker = term.data[0];
  return Type.isAtom(marker) && marker.value === "set";
}

function getSetElements(set) {
  if (!isSet(set)) {
    Interpreter.raiseArgumentError("argument error");
  }

  // Elements are stored in the third position of the tuple
  return set.data[2].data;
}

function createSet(elements) {
  // Create a set tuple: {set, Version, ElementsList}
  return Type.tuple([
    Type.atom("set"),
    Type.integer(2), // Version 2
    Type.list(elements),
  ]);
}

const Erlang_Sets = {
  // Start all/2
  "all/2": (predicate, set) => {
    if (!Type.isAnonymousFunction(predicate) || predicate.arity !== 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a fun that takes one argument",
        ),
      );
    }

    const elements = getSetElements(set);

    for (const element of elements) {
      const result = Interpreter.callAnonymousFunction(predicate, [element]);

      if (Type.isFalse(result)) {
        return Type.boolean(false);
      }
    }

    return Type.boolean(true);
  },
  // End all/2
  // Deps: []

  // Start filter/2
  "filter/2": (predicate, set) => {
    if (!Type.isAnonymousFunction(predicate) || predicate.arity !== 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a fun that takes one argument",
        ),
      );
    }

    const elements = getSetElements(set);
    const filtered = [];

    for (const element of elements) {
      const result = Interpreter.callAnonymousFunction(predicate, [element]);

      if (!Type.isFalse(result)) {
        filtered.push(element);
      }
    }

    return createSet(filtered);
  },
  // End filter/2
  // Deps: []
};

export default Erlang_Sets;
