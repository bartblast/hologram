"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Maps = {
  // Start find/2
  "find/2": (key, map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    const encodedKey = Type.encodeMapKey(key);

    if (map.data[encodedKey]) {
      return map.data[encodedKey][1];
    }

    return Type.atom("error");
  },
  // End find/2
  // Deps: []

  // Start fold/3
  "fold/3": (fun, initialAcc, map) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 3) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
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

  // Start from_keys/2
  "from_keys/2": (keys, value) => {
    if (!Type.isList(keys)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isProperList(keys)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a proper list"),
      );
    }

    return Type.map(keys.data.map((key) => [key, value]));
  },
  // End from_keys/2
  // Deps: []

  // Start from_list/1
  "from_list/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
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

    Interpreter.raiseKeyError(Interpreter.buildKeyErrorMsg(key, map));
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

  // Start intersect/2
  "intersect/2": (map1, map2) => {
    if (!Type.isMap(map1)) {
      Interpreter.raiseBadMapError(map1);
    }
    if (!Type.isMap(map2)) {
      Interpreter.raiseBadMapError(map2);
    }

    return Type.map(
      Object.keys(map1.data).reduce((acc, key) => {
        if (map2.data[key]) {
          acc.push(map2.data[key]);
        }
        return acc;
      }, []),
    );
  },
  // End intersect/2
  // Deps: []

  // Start intersect_with/3
  "intersect_with/3": (fun, map1, map2) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 3) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a fun that takes three arguments",
        ),
      );
    }

    if (!Type.isMap(map1)) {
      Interpreter.raiseBadMapError(map1);
    }
    if (!Type.isMap(map2)) {
      Interpreter.raiseBadMapError(map2);
    }

    const result = Type.map();

    Object.values(map1.data).forEach(([key, value]) => {
      const encodedKey = Type.encodeMapKey(key);
      const keyValue2 = map2.data[encodedKey];

      if (keyValue2) {
        result.data[encodedKey] = [
          key,
          Interpreter.callAnonymousFunction(fun, [key, value, keyValue2[1]]),
        ];
      }
    });

    return result;
  },
  // End intersect_with/3
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

  // Start iterator/1
  "iterator/1": (map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    return Type.improperList([Type.integer(0), map]);
  },
  // End iterator/1
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
        Interpreter.buildArgumentErrorMsg(
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

  // Start merge_with/3
  "merge_with/3": (combiner, map1, map2) => {
    if (!Type.isAnonymousFunction(combiner) || combiner.arity !== 3) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a fun that takes three arguments",
        ),
      );
    }

    if (!Type.isMap(map1)) {
      Interpreter.raiseBadMapError(map1);
    }

    if (!Type.isMap(map2)) {
      Interpreter.raiseBadMapError(map2);
    }

    const result = Type.cloneMap(map1);

    Object.entries(map2.data).forEach(([encodedKey, [key, value2]]) => {
      const value1 = result.data[encodedKey]?.[1];

      const newValue = value1
        ? Interpreter.callAnonymousFunction(combiner, [key, value1, value2])
        : value2;

      result.data[encodedKey] = [key, newValue];
    });

    return result;
  },
  // End merge_with/3
  // Deps: []

  // Start next/1
  "next/1": (iterator) => {
    if (!Type.isIterator(iterator)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a valid iterator"),
      );
    }

    if (Type.isTuple(iterator)) {
      return iterator;
    }

    if (Type.isImproperList(iterator)) {
      return Object.values(iterator.data[1].data)
        .reverse()
        .reduce(
          (acc, [key, value]) => Type.tuple([key, value, acc]),
          Type.atom("none"),
        );
    }

    return Type.atom("none");
  },
  // End next/1
  // Deps: []

  // Start put/3
  "put/3": (key, value, map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    const newMap = Type.cloneMap(map);
    newMap.data[Type.encodeMapKey(key)] = [key, value];

    return newMap;
  },
  // End put/3
  // Deps: []

  // Start remove/2
  "remove/2": (key, map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    const newMap = Type.cloneMap(map);
    delete newMap.data[Type.encodeMapKey(key)];

    return newMap;
  },
  // End remove/2
  // Deps: []

  // Start take/2
  "take/2": (key, map) => {
    const value = Erlang_Maps["get/3"](key, map, null);

    if (value === null) {
      return Type.atom("error");
    }

    const newMap = Erlang_Maps["remove/2"](key, map);

    return Type.tuple([value, newMap]);
  },
  // End take/2
  // Deps: [:maps.get/3, :maps.remove/2]

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

  // Start update/3
  "update/3": (key, value, map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    if (Type.isFalse(Erlang_Maps["is_key/2"](key, map))) {
      Interpreter.raiseKeyError(Interpreter.buildKeyErrorMsg(key, map));
    }

    return Erlang_Maps["put/3"](key, value, map);
  },
  // End update/3
  // Deps: [:maps.is_key/2, :maps.put/3]

  // Start values/1
  "values/1": (map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    return Type.list(Object.values(map.data).map(([_key, value]) => value));
  },
  // End values/1
  // Deps: []
};

export default Erlang_Maps;
