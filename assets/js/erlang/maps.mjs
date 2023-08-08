"use strict";

import Hologram from "../hologram.mjs";
import Type from "../type.mjs";

/*
MFAs for sorting:
[
  {:maps, :get, 2}
]
|> Enum.sort()
*/

const Erlang_maps = {
  // start get/2
  "get/2": (key, map) => {
    if (!Type.isMap(map)) {
      Hologram.raiseBadMapError(
        `expected a map, got: ${Hologram.inspect(map)}`
      );
    }

    const encodedKey = Type.encodeMapKey(key);

    if (map.data[encodedKey]) {
      return map.data[encodedKey][1];
    }

    Hologram.raiseKeyError(
      `key ${Hologram.inspect(key)} not found in ${Hologram.inspect(map)}`
    );
  },
  // end get/2
  // deps: []
};

export default Erlang_maps;
