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
      Interpreter.raiseBifError(["badmap", map], "maps", "find", [key, map]);
    }

    const encodedKey = Type.encodeMapKey(key);

    if (map.data[encodedKey]) {
      return Type.tuple([Type.atom("ok"), map.data[encodedKey][1]]);
    }

    return Type.atom("error");
  },
  // End find/2
  // Deps: []

  // TODO: implement iterators
  // Start fold/3
  "fold/3": (fun, initialAcc, map) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 3) {
      Interpreter.raiseBifError("badarg", "maps", "fold", [
        fun,
        initialAcc,
        map,
      ]);
    }

    if (!Type.isMap(map)) {
      Interpreter.raiseBifError(["badmap", map], "maps", "fold", [
        fun,
        initialAcc,
        map,
      ]);
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
    if (!Type.isProperList(keys)) {
      Interpreter.raiseBifError("badarg", "maps", "from_keys", [keys, value]);
    }

    return Type.map(keys.data.map((key) => [key, value]));
  },
  // End from_keys/2
  // Deps: []

  // Start from_list/1
  "from_list/1": (list) => {
    const isPair = (elem) => Type.isTuple(elem) && elem.data.length === 2;

    // An element that isn't a pair derives the bare "argument error", since the
    // fragment the message is built from names only what is wrong with the
    // argument as a whole - which is a list, whatever it holds.
    if (!Type.isProperList(list) || !list.data.every(isPair)) {
      Interpreter.raiseBifError("badarg", "maps", "from_list", [list]);
    }

    return Type.map(list.data.map((tuple) => tuple.data));
  },
  // End from_list/1
  // Deps: []

  // The BEAM implements this function with the map_get BIF, so its errors
  // report the :erlang.map_get/2 identity with erts error_info.
  // Start get/2
  "get/2": (key, map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBifError(["badmap", map], "erlang", "map_get", [
        key,
        map,
      ]);
    }

    const encodedKey = Type.encodeMapKey(key);

    if (map.data[encodedKey]) {
      return map.data[encodedKey][1];
    }

    Interpreter.raiseBifError(["badkey", key], "erlang", "map_get", [key, map]);
  },
  // End get/2
  // Deps: []

  // Start get/3
  "get/3": (key, map, defaultValue) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseFramelessError(["badmap", map]);
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
      Interpreter.raiseBifError(["badmap", map1], "maps", "intersect", [
        map1,
        map2,
      ]);
    }

    if (!Type.isMap(map2)) {
      Interpreter.raiseBifError(["badmap", map2], "maps", "intersect", [
        map1,
        map2,
      ]);
    }

    const result = Type.map();

    for (const encodedKey of Object.keys(map1.data)) {
      if (encodedKey in map2.data) {
        result.data[encodedKey] = map2.data[encodedKey];
      }
    }

    return result;
  },
  // End intersect/2
  // Deps: []

  // Start intersect_with/3
  "intersect_with/3": (fun, map1, map2) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 3) {
      Interpreter.raiseBifError("badarg", "maps", "intersect_with", [
        fun,
        map1,
        map2,
      ]);
    }

    if (!Type.isMap(map1)) {
      Interpreter.raiseBifError(["badmap", map1], "maps", "intersect_with", [
        fun,
        map1,
        map2,
      ]);
    }

    if (!Type.isMap(map2)) {
      Interpreter.raiseBifError(["badmap", map2], "maps", "intersect_with", [
        fun,
        map1,
        map2,
      ]);
    }

    const result = Type.map();

    for (const [encodedKey, [key, value]] of Object.entries(map1.data)) {
      if (encodedKey in map2.data) {
        result.data[encodedKey] = [
          key,
          Interpreter.callAnonymousFunction(fun, [
            key,
            value,
            map2.data[encodedKey][1],
          ]),
        ];
      }
    }

    return result;
  },
  // End intersect_with/3
  // Deps: []

  // Doc-hidden OTP internal (-doc false), exported for :erl_stdlib_errors.
  // Covers the iterator shapes the client can produce: the :none atom,
  // {key, value, iterator} tuples (validated recursively, unlike the shallow
  // shape check next/1 uses), and the [path | map] improper list form.
  // Start is_iterator_valid/1
  "is_iterator_valid/1": (iterator) => {
    let current = iterator;

    while (Type.isTuple(current) && current.data.length === 3) {
      current = current.data[2];
    }

    if (Type.isAtom(current) && current.value === "none") {
      return Type.boolean(true);
    }

    return Type.boolean(
      Type.isImproperList(current) &&
        current.data.length === 2 &&
        Type.isInteger(current.data[0]) &&
        Type.isMap(current.data[1]),
    );
  },
  // End is_iterator_valid/1
  // Deps: []

  // The BEAM implements this function with the is_map_key BIF, so its errors
  // report the :erlang.is_map_key/2 identity with erts error_info.
  // Start is_key/2
  "is_key/2": (key, map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBifError(["badmap", map], "erlang", "is_map_key", [
        key,
        map,
      ]);
    }

    return Type.boolean(Type.encodeMapKey(key) in map.data);
  },
  // End is_key/2
  // Deps: []

  // Start iterator/1
  "iterator/1": (map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBifError(["badmap", map], "maps", "iterator", [map]);
    }

    return Type.improperList([Type.integer(0), map]);
  },
  // End iterator/1
  // Deps: []

  // Start keys/1
  "keys/1": (map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBifError(["badmap", map], "maps", "keys", [map]);
    }

    return Type.list(Object.values(map.data).map(([key, _value]) => key));
  },
  // End keys/1
  // Deps: []

  // TODO: implement iterators
  // Start map/2
  "map/2": (fun, mapOrIterator) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 2) {
      Interpreter.raiseBifError("badarg", "maps", "map", [fun, mapOrIterator]);
    }

    if (!Type.isMap(mapOrIterator)) {
      Interpreter.raiseBifError(["badmap", mapOrIterator], "maps", "map", [
        fun,
        mapOrIterator,
      ]);
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
      Interpreter.raiseBifError(["badmap", map1], "maps", "merge", [
        map1,
        map2,
      ]);
    }

    if (!Type.isMap(map2)) {
      Interpreter.raiseBifError(["badmap", map2], "maps", "merge", [
        map1,
        map2,
      ]);
    }

    return {type: "map", data: {...map1.data, ...map2.data}};
  },
  // End merge/2
  // Deps: []

  // Start merge_with/3
  "merge_with/3": (combiner, map1, map2) => {
    if (!Type.isAnonymousFunction(combiner) || combiner.arity !== 3) {
      Interpreter.raiseBifError("badarg", "maps", "merge_with", [
        combiner,
        map1,
        map2,
      ]);
    }

    if (!Type.isMap(map1)) {
      Interpreter.raiseBifError(["badmap", map1], "maps", "merge_with", [
        combiner,
        map1,
        map2,
      ]);
    }

    if (!Type.isMap(map2)) {
      Interpreter.raiseBifError(["badmap", map2], "maps", "merge_with", [
        combiner,
        map1,
        map2,
      ]);
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
    // Accepts what maps:next/1 accepts, without validating tuple tails: any
    // {key, value, iterator} tuple, a [path | map] improper list, or :none -
    // unlike the recursive is_iterator_valid/1.
    const isIteratorShaped =
      (Type.isTuple(iterator) && iterator.data.length === 3) ||
      (Type.isImproperList(iterator) &&
        iterator.data.length === 2 &&
        Type.isInteger(iterator.data[0]) &&
        Type.isMap(iterator.data[1])) ||
      (Type.isAtom(iterator) && iterator.value === "none");

    if (!isIteratorShaped) {
      Interpreter.raiseBifError("badarg", "maps", "next", [iterator]);
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
      Interpreter.raiseBifError(["badmap", map], "maps", "put", [
        key,
        value,
        map,
      ]);
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
      Interpreter.raiseBifError(["badmap", map], "maps", "remove", [key, map]);
    }

    const newMap = Type.cloneMap(map);
    delete newMap.data[Type.encodeMapKey(key)];

    return newMap;
  },
  // End remove/2
  // Deps: []

  // Start take/2
  "take/2": (key, map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBifError(["badmap", map], "maps", "take", [key, map]);
    }

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
      Interpreter.raiseBifError(["badmap", mapOrIterator], "maps", "to_list", [
        mapOrIterator,
      ]);
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
      Interpreter.raiseBifError(["badmap", map], "maps", "update", [
        key,
        value,
        map,
      ]);
    }

    if (Type.isFalse(Erlang_Maps["is_key/2"](key, map))) {
      Interpreter.raiseBifError(["badkey", key], "maps", "update", [
        key,
        value,
        map,
      ]);
    }

    return Erlang_Maps["put/3"](key, value, map);
  },
  // End update/3
  // Deps: [:maps.is_key/2, :maps.put/3]

  // Start values/1
  "values/1": (map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBifError(["badmap", map], "maps", "values", [map]);
    }

    return Type.list(Object.values(map.data).map(([_key, value]) => value));
  },
  // End values/1
  // Deps: []
};

export default Erlang_Maps;
