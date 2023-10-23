"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

/*
MFAs for sorting:
[
  {:maps, :get, 2}
]
|> Enum.sort()
*/

const Erlang_Maps = {
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
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    const encodedKey = Type.encodeMapKey(key);

    if (map.data[encodedKey]) {
      return map.data[encodedKey][1];
    }

    Interpreter.raiseKeyError(
      `key ${Interpreter.inspect(key)} not found in ${Interpreter.inspect(
        map,
      )}`,
    );
  },
  // end get/2
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
};

export default Erlang_Maps;
