"use strict";

import Hologram from "../hologram.mjs";

const Type = Hologram.Type;

const Erlang_maps = {
  // supported arities: 2
  // start: get
  get: (key, map) => {
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
  // end: get
};

export default Erlang_maps;
