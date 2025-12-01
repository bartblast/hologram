"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";
import Utils from "../utils.mjs";

const Erlang_Sets = {
  // Start subtract/2
  "subtract/2": (set1, set2) => {
    if (!Type.isMap(set1)) {
      Interpreter.raiseBadMapError(set1);
    }

    if (!Type.isMap(set2)) {
      Interpreter.raiseBadMapError(set2);
    }

    const result = Utils.shallowCloneObject(set1);
    // Need to clone the data object as well since we'll be mutating it
    result.data = {...set1.data};

    for (const encodedKey of Object.keys(set2.data)) {
      delete result.data[encodedKey];
    }

    return result;
  },
  // End subtract/2
  // Deps: []

  // Start union/2
  "union/2": (set1, set2) => {
    if (!Type.isMap(set1)) {
      Interpreter.raiseBadMapError(set1);
    }

    if (!Type.isMap(set2)) {
      Interpreter.raiseBadMapError(set2);
    }

    return {type: "map", data: {...set1.data, ...set2.data}};
  },
  // End union/2
  // Deps: []
};

export default Erlang_Sets;
