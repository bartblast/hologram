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
  // start get/2
  "get/2": (key, map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(
        `expected a map, got: ${Interpreter.inspect(map)}`,
      );
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
};

export default Erlang_Maps;
