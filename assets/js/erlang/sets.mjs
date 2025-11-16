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

  // Start any/2
  "any/2": (predicate, set) => {
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

      if (!Type.isFalse(result)) {
        return Type.boolean(true);
      }
    }

    return Type.boolean(false);
  },
  // End any/2
  // Deps: []

  // Start fold/3
  "fold/3": (fun, initialAcc, set) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a fun that takes two arguments",
        ),
      );
    }

    const elements = getSetElements(set);
    let acc = initialAcc;

    for (const element of elements) {
      acc = Interpreter.callAnonymousFunction(fun, [element, acc]);
    }

    return acc;
  },
  // End fold/3
  // Deps: []

  // Start intersection/2
  "intersection/2": (set1, set2) => {
    const elements1 = getSetElements(set1);
    const elements2 = getSetElements(set2);

    // Create a map for fast lookup
    const set2Map = new Map();
    for (const elem of elements2) {
      const key = Type.encodeMapKey(elem);
      set2Map.set(key, elem);
    }

    // Find common elements
    const intersection = [];
    for (const elem of elements1) {
      const key = Type.encodeMapKey(elem);
      if (set2Map.has(key)) {
        intersection.push(elem);
      }
    }

    return createSet(intersection);
  },
  // End intersection/2
  // Deps: []

  // Start is_disjoint/2
  "is_disjoint/2": (set1, set2) => {
    const elements1 = getSetElements(set1);
    const elements2 = getSetElements(set2);

    // Create a map for fast lookup
    const set2Map = new Map();
    for (const elem of elements2) {
      const key = Type.encodeMapKey(elem);
      set2Map.set(key, elem);
    }

    // Check if any element from set1 exists in set2
    for (const elem of elements1) {
      const key = Type.encodeMapKey(elem);
      if (set2Map.has(key)) {
        return Type.boolean(false);
      }
    }

    return Type.boolean(true);
  },
  // End is_disjoint/2
  // Deps: []

  // Start is_subset/2
  "is_subset/2": (set1, set2) => {
    const elements1 = getSetElements(set1);
    const elements2 = getSetElements(set2);

    // Create a map for fast lookup
    const set2Map = new Map();
    for (const elem of elements2) {
      const key = Type.encodeMapKey(elem);
      set2Map.set(key, elem);
    }

    // Check if all elements from set1 exist in set2
    for (const elem of elements1) {
      const key = Type.encodeMapKey(elem);
      if (!set2Map.has(key)) {
        return Type.boolean(false);
      }
    }

    return Type.boolean(true);
  },
  // End is_subset/2
  // Deps: []

  // Start add_element/2
  "add_element/2": (element, set) => {
    const elements = getSetElements(set);

    // Check if element already exists
    for (const elem of elements) {
      const key = Type.encodeMapKey(elem);
      const newKey = Type.encodeMapKey(element);
      if (key === newKey) {
        // Element already in set, return unchanged
        return set;
      }
    }

    // Add element to set
    const newElements = [...elements, element];
    return createSet(newElements);
  },
  // End add_element/2
  // Deps: []

  // Start del_element/2
  "del_element/2": (element, set) => {
    const elements = getSetElements(set);
    const elementKey = Type.encodeMapKey(element);

    // Filter out the element
    const filtered = elements.filter((elem) => {
      return Type.encodeMapKey(elem) !== elementKey;
    });

    return createSet(filtered);
  },
  // End del_element/2
  // Deps: []

  // Start from_list/1
  "from_list/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    // Create set from list, removing duplicates
    const seen = new Map();
    const unique = [];

    for (const elem of list.data) {
      const key = Type.encodeMapKey(elem);
      if (!seen.has(key)) {
        seen.set(key, true);
        unique.push(elem);
      }
    }

    return createSet(unique);
  },
  // End from_list/1
  // Deps: []
};

export default Erlang_Sets;
