"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// GB trees (General Balanced trees) are self-balancing binary search trees
// Simplified implementation using a map internally

function isTree(term) {
  if (!Type.isTuple(term) || term.data.length < 2) {
    return false;
  }
  const marker = term.data[0];
  return Type.isAtom(marker) && marker.value === "gb_tree";
}

function createTree(data = {}) {
  return Type.tuple([
    Type.atom("gb_tree"),
    Type.map(Object.values(data))
  ]);
}

const Erlang_Gb_Trees = {
  // Start empty/0
  "empty/0": () => {
    return createTree();
  },
  // End empty/0
  // Deps: []

  // Start insert/3
  "insert/3": (key, value, tree) => {
    if (!isTree(tree)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a gb_tree"),
      );
    }

    const data = tree.data[1].data;
    const encodedKey = Type.encodeMapKey(key);

    // Check if key already exists
    if (data[encodedKey]) {
      Interpreter.raiseArgumentError("key already exists");
    }

    const newData = {...data};
    newData[encodedKey] = [key, value];

    return Type.tuple([
      Type.atom("gb_tree"),
      Type.map(Object.values(newData))
    ]);
  },
  // End insert/3
  // Deps: []

  // Start enter/3
  "enter/3": (key, value, tree) => {
    if (!isTree(tree)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a gb_tree"),
      );
    }

    const data = tree.data[1].data;
    const encodedKey = Type.encodeMapKey(key);

    const newData = {...data};
    newData[encodedKey] = [key, value];

    return Type.tuple([
      Type.atom("gb_tree"),
      Type.map(Object.values(newData))
    ]);
  },
  // End enter/3
  // Deps: []

  // Start lookup/2
  "lookup/2": (key, tree) => {
    if (!isTree(tree)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a gb_tree"),
      );
    }

    const data = tree.data[1].data;
    const encodedKey = Type.encodeMapKey(key);

    if (data[encodedKey]) {
      return Type.tuple([Type.atom("value"), data[encodedKey][1]]);
    }

    return Type.atom("none");
  },
  // End lookup/2
  // Deps: []

  // Start get/2
  "get/2": (key, tree) => {
    if (!isTree(tree)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a gb_tree"),
      );
    }

    const data = tree.data[1].data;
    const encodedKey = Type.encodeMapKey(key);

    if (data[encodedKey]) {
      return data[encodedKey][1];
    }

    Interpreter.raiseArgumentError("key not found");
  },
  // End get/2
  // Deps: []

  // Start delete/2
  "delete/2": (key, tree) => {
    if (!isTree(tree)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a gb_tree"),
      );
    }

    const data = tree.data[1].data;
    const encodedKey = Type.encodeMapKey(key);

    const newData = {...data};
    delete newData[encodedKey];

    return Type.tuple([
      Type.atom("gb_tree"),
      Type.map(Object.values(newData))
    ]);
  },
  // End delete/2
  // Deps: []

  // Start is_empty/1
  "is_empty/1": (tree) => {
    if (!isTree(tree)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a gb_tree"),
      );
    }

    const data = tree.data[1].data;
    return Type.boolean(Object.keys(data).length === 0);
  },
  // End is_empty/1
  // Deps: []

  // Start size/1
  "size/1": (tree) => {
    if (!isTree(tree)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a gb_tree"),
      );
    }

    const data = tree.data[1].data;
    return Type.integer(Object.keys(data).length);
  },
  // End size/1
  // Deps: []

  // Start to_list/1
  "to_list/1": (tree) => {
    if (!isTree(tree)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a gb_tree"),
      );
    }

    const data = tree.data[1].data;
    const list = Object.values(data).map(([key, value]) => Type.tuple([key, value]));

    // Sort by key for consistent ordering
    list.sort((a, b) => Interpreter.compareTerms(a.data[0], b.data[0]));

    return Type.list(list);
  },
  // End to_list/1
  // Deps: []

  // Start from_orddict/1
  "from_orddict/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    const data = {};

    for (const item of list.data) {
      if (!Type.isTuple(item) || item.data.length !== 2) {
        Interpreter.raiseArgumentError("argument error");
      }

      const [key, value] = item.data;
      const encodedKey = Type.encodeMapKey(key);
      data[encodedKey] = [key, value];
    }

    return Type.tuple([
      Type.atom("gb_tree"),
      Type.map(Object.values(data))
    ]);
  },
  // End from_orddict/1
  // Deps: []
};

export default Erlang_Gb_Trees;
