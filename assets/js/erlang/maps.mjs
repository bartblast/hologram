"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in a "deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.Compiler.list_runtime_mfas/1.

const Erlang_Maps = {
  // start fold/3
  "fold/3": (fun, initialAcc, map) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 3) {
      Interpreter.raiseArgumentError(
        "errors were found at the given arguments:\n\n* 1st argument: not a fun that takes three arguments",
      );
    }

    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    return Object.values(map.data).reduce(
      (acc, [key, value]) =>
        Interpreter.callAnonymousFunction(fun, [key, value, acc]),
      initialAcc,
    );
  },
  // end fold/3
  // deps: []

  // start from_list/1
  "from_list/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        "errors were found at the given arguments:\n\n* 1st argument: not a list",
      );
    }

    return Type.map(list.data.map((tuple) => tuple.data));
  },
  // end from_list/1
  // deps: []

  // start get/2
  "get/2": (key, map) => {
    const value = Erlang_Maps["get/3"](key, map, null);

    if (value !== null) {
      return value;
    }

    Interpreter.raiseKeyError(
      `key ${Interpreter.inspect(key)} not found in: ${Interpreter.inspect(
        map,
      )}`,
    );
  },
  // end get/2
  // deps: [:maps.get/3]

  // start get/3
  "get/3": (key, map, defaultValue) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    const encodedKey = Type.encodeMapKey(key);

    if (map.data[encodedKey]) {
      return map.data[encodedKey][1];
    }

    return defaultValue;
  },
  // end get/3
  // deps: []

  // start is_key/2
  "is_key/2": (key, map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    return Type.boolean(Type.encodeMapKey(key) in map.data);
  },
  // end is_key/2
  // deps: []

  // start merge/2
  "merge/2": (map1, map2) => {
    if (!Type.isMap(map1)) {
      Interpreter.raiseBadMapError(map1);
    }

    if (!Type.isMap(map2)) {
      Interpreter.raiseBadMapError(map2);
    }

    return {type: "map", data: {...map1.data, ...map2.data}};
  },
  // end merge/2
  // deps: []

  // start put/3
  "put/3": (key, value, map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    const newMap = Interpreter.cloneVars(map);
    newMap.data[Type.encodeMapKey(key)] = [key, value];

    return newMap;
  },
  // end put/3
  // deps: []

  // TODO: implement iterators
  // start to_list/1
  "to_list/1": (mapOrIterator) => {
    if (!Type.isMap(mapOrIterator)) {
      Interpreter.raiseBadMapError(mapOrIterator);
    }

    return Type.list(
      Object.values(mapOrIterator.data).map((item) => Type.tuple(item)),
    );
  },
  // end to_list/1
  // deps: []
};

export default Erlang_Maps;
