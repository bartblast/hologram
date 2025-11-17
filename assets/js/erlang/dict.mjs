"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// Erlang dict is represented as a tuple with version and internal structure
// For simplicity, we represent it as {dict, Version, Data} where Data is a Map

function isDict(term) {
  if (!Type.isTuple(term) || term.data.length < 3) {
    return false;
  }
  const marker = term.data[0];
  return Type.isAtom(marker) && marker.value === "dict";
}

function createDict(dataMap = {}) {
  return Type.tuple([
    Type.atom("dict"),
    Type.integer(2), // Version
    Type.map(Object.entries(dataMap).map(([k, v]) => [Type.bitstring(k), v]))
  ]);
}

function getDictData(dict) {
  if (!isDict(dict)) {
    Interpreter.raiseArgumentError("argument error");
  }
  return dict.data[2].data;
}

const Erlang_Dict = {
  // Start new/0
  "new/0": () => {
    return createDict();
  },
  // End new/0
  // Deps: []

  // Start store/3
  "store/3": (key, value, dict) => {
    if (!isDict(dict)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a dict"),
      );
    }

    const encodedKey = Type.encodeMapKey(key);
    const data = getDictData(dict);
    const newData = {...data};
    newData[encodedKey] = [key, value];

    return Type.tuple([
      Type.atom("dict"),
      Type.integer(2),
      Type.map(Object.values(newData))
    ]);
  },
  // End store/3
  // Deps: []

  // Start find/2
  "find/2": (key, dict) => {
    if (!isDict(dict)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a dict"),
      );
    }

    const encodedKey = Type.encodeMapKey(key);
    const data = getDictData(dict);

    if (data[encodedKey]) {
      return Type.tuple([Type.atom("ok"), data[encodedKey][1]]);
    }

    return Type.atom("error");
  },
  // End find/2
  // Deps: []

  // Start fetch/2
  "fetch/2": (key, dict) => {
    if (!isDict(dict)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a dict"),
      );
    }

    const encodedKey = Type.encodeMapKey(key);
    const data = getDictData(dict);

    if (data[encodedKey]) {
      return data[encodedKey][1];
    }

    Interpreter.raiseArgumentError("argument error");
  },
  // End fetch/2
  // Deps: []

  // Start erase/2
  "erase/2": (key, dict) => {
    if (!isDict(dict)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a dict"),
      );
    }

    const encodedKey = Type.encodeMapKey(key);
    const data = getDictData(dict);
    const newData = {...data};
    delete newData[encodedKey];

    return Type.tuple([
      Type.atom("dict"),
      Type.integer(2),
      Type.map(Object.values(newData))
    ]);
  },
  // End erase/2
  // Deps: []

  // Start size/1
  "size/1": (dict) => {
    if (!isDict(dict)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a dict"),
      );
    }

    const data = getDictData(dict);
    return Type.integer(Object.keys(data).length);
  },
  // End size/1
  // Deps: []

  // Start to_list/1
  "to_list/1": (dict) => {
    if (!isDict(dict)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a dict"),
      );
    }

    const data = getDictData(dict);
    const list = Object.values(data).map(([key, value]) => Type.tuple([key, value]));
    return Type.list(list);
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

    const dataMap = {};

    for (const item of list.data) {
      if (!Type.isTuple(item) || item.data.length !== 2) {
        Interpreter.raiseArgumentError("argument error");
      }

      const [key, value] = item.data;
      const encodedKey = Type.encodeMapKey(key);
      dataMap[encodedKey] = [key, value];
    }

    return Type.tuple([
      Type.atom("dict"),
      Type.integer(2),
      Type.map(Object.values(dataMap))
    ]);
  },
  // End from_list/1
  // Deps: []
};

export default Erlang_Dict;
