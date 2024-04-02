"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";
import Utils from "../utils.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in a "deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.Compiler.list_runtime_mfas/1.

const Erlang_Maps = {
  // Start fold/3
  "fold/3": (fun, initialAcc, map) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 3) {
      Interpreter.raiseArgumentError(
        Interpreter.buildErrorsFoundMsg(
          1,
          "not a fun that takes three arguments",
        ),
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
  // End fold/3
  // Deps: []

  // Start from_list/1
  "from_list/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildErrorsFoundMsg(1, "not a list"),
      );
    }

    return Type.map(list.data.map((tuple) => tuple.data));
  },
  // End from_list/1
  // Deps: []

  // Start get/2
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
  // End get/2
  // Deps: [:maps.get/3]

  // Start get/3
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
  // End get/3
  // Deps: []

  // Start is_key/2
  "is_key/2": (key, map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    return Type.boolean(Type.encodeMapKey(key) in map.data);
  },
  // End is_key/2
  // Deps: []

  // Start keys/1
  "keys/1": (map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    return Type.list(Object.values(map.data).map(([key, _value]) => key));
  },
  // End keys/1
  // Deps: []

  // TODO: implement iterators
  // Start map/2
  "map/2": (fun, mapOrIterator) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseArgumentError(
        Interpreter.buildErrorsFoundMsg(
          1,
          "not a fun that takes two arguments",
        ),
      );
    }

    if (!Type.isMap(mapOrIterator)) {
      Interpreter.raiseBadMapError(mapOrIterator);
    }

    return Type.map(
      Object.values(mapOrIterator.data).map(([key, value]) => [
        key,
        Interpreter.callAnonymousFunction(fun, [key, value]),
      ]),
    );
  },
  // End map/2
  // Deps: []

  // Start merge/2
  "merge/2": (map1, map2) => {
    if (!Type.isMap(map1)) {
      Interpreter.raiseBadMapError(map1);
    }

    if (!Type.isMap(map2)) {
      Interpreter.raiseBadMapError(map2);
    }

    return {type: "map", data: {...map1.data, ...map2.data}};
  },
  // End merge/2
  // Deps: []

  // Start put/3
  "put/3": (key, value, map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    const newMap = Utils.cloneDeep(map);
    newMap.data[Type.encodeMapKey(key)] = [key, value];

    return newMap;
  },
  // End put/3
  // Deps: []

  // TODO: implement iterators
  // Start to_list/1
  "to_list/1": (mapOrIterator) => {
    if (!Type.isMap(mapOrIterator)) {
      Interpreter.raiseBadMapError(mapOrIterator);
    }

    return Type.list(
      Object.values(mapOrIterator.data).map((item) => Type.tuple(item)),
    );
  },
  // End to_list/1
  // Deps: []
};

export default Erlang_Maps;
