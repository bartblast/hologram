"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// GB sets (General Balanced sets) are self-balancing binary search trees for sets
// Simplified implementation using a Set-like structure

function isGbSet(term) {
  if (!Type.isTuple(term) || term.data.length < 2) {
    return false;
  }
  const marker = term.data[0];
  return Type.isAtom(marker) && marker.value === "gb_set";
}

function createGbSet(elements = []) {
  // Store unique elements
  const uniqueMap = new Map();
  for (const elem of elements) {
    const key = Type.encodeMapKey(elem);
    uniqueMap.set(key, elem);
  }

  return Type.tuple([
    Type.atom("gb_set"),
    Type.list(Array.from(uniqueMap.values()))
  ]);
}

function getGbSetElements(set) {
  if (!isGbSet(set)) {
    Interpreter.raiseArgumentError("argument error");
  }
  return set.data[1].data;
}

const Erlang_Gb_Sets = {
  // Start empty/0
  "empty/0": () => {
    return createGbSet([]);
  },
  // End empty/0
  // Deps: []

  // Start add/2
  "add/2": (element, set) => {
    if (!isGbSet(set)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a gb_set"),
      );
    }

    const elements = getGbSetElements(set);
    const elementKey = Type.encodeMapKey(element);

    // Check if element already exists
    for (const elem of elements) {
      const key = Type.encodeMapKey(elem);
      if (key === elementKey) {
        // Element already in set, return unchanged
        return set;
      }
    }

    // Add element
    return createGbSet([...elements, element]);
  },
  // End add/2
  // Deps: []

  // Start add_element/2
  "add_element/2": (element, set) => {
    // add_element/2 is an alias for add/2
    return Erlang_Gb_Sets["add/2"](element, set);
  },
  // End add_element/2
  // Deps: [:gb_sets.add/2]

  // Start is_member/2
  "is_member/2": (element, set) => {
    if (!isGbSet(set)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a gb_set"),
      );
    }

    const elements = getGbSetElements(set);
    const elementKey = Type.encodeMapKey(element);

    for (const elem of elements) {
      const key = Type.encodeMapKey(elem);
      if (key === elementKey) {
        return Type.boolean(true);
      }
    }

    return Type.boolean(false);
  },
  // End is_member/2
  // Deps: []

  // Start delete/2
  "delete/2": (element, set) => {
    if (!isGbSet(set)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a gb_set"),
      );
    }

    const elements = getGbSetElements(set);
    const elementKey = Type.encodeMapKey(element);

    const filtered = elements.filter((elem) => {
      return Type.encodeMapKey(elem) !== elementKey;
    });

    return createGbSet(filtered);
  },
  // End delete/2
  // Deps: []

  // Start size/1
  "size/1": (set) => {
    if (!isGbSet(set)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a gb_set"),
      );
    }

    const elements = getGbSetElements(set);
    return Type.integer(elements.length);
  },
  // End size/1
  // Deps: []

  // Start is_empty/1
  "is_empty/1": (set) => {
    if (!isGbSet(set)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a gb_set"),
      );
    }

    const elements = getGbSetElements(set);
    return Type.boolean(elements.length === 0);
  },
  // End is_empty/1
  // Deps: []

  // Start to_list/1
  "to_list/1": (set) => {
    if (!isGbSet(set)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a gb_set"),
      );
    }

    const elements = getGbSetElements(set);
    // Sort elements for consistent ordering
    const sorted = [...elements].sort((a, b) => Interpreter.compareTerms(a, b));
    return Type.list(sorted);
  },
  // End to_list/1
  // Deps: []

  // Start from_list/1
  "from_list/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    return createGbSet(list.data);
  },
  // End from_list/1
  // Deps: []

  // Start union/2
  "union/2": (set1, set2) => {
    if (!isGbSet(set1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a gb_set"),
      );
    }

    if (!isGbSet(set2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a gb_set"),
      );
    }

    const elements1 = getGbSetElements(set1);
    const elements2 = getGbSetElements(set2);

    return createGbSet([...elements1, ...elements2]);
  },
  // End union/2
  // Deps: []

  // Start intersection/2
  "intersection/2": (set1, set2) => {
    if (!isGbSet(set1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a gb_set"),
      );
    }

    if (!isGbSet(set2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a gb_set"),
      );
    }

    const elements1 = getGbSetElements(set1);
    const elements2 = getGbSetElements(set2);

    // Create a map of set2 elements for fast lookup
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

    return createGbSet(intersection);
  },
  // End intersection/2
  // Deps: []
};

export default Erlang_Gb_Sets;
