"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";
import Utils from "../utils.mjs";

const Erlang_Sets = {
  // Start intersection/2
  "intersection/2": (set1, set2) => {
    if (!Type.isMap(set1)) {
      Interpreter.raiseBadMapError(set1);
    }

    if (!Type.isMap(set2)) {
      Interpreter.raiseBadMapError(set2);
    }

    const resultData = {};

    for (const encodedKey of Object.keys(set1.data)) {
      if (set2.data[encodedKey]) {
        resultData[encodedKey] = set1.data[encodedKey];
      }
    }

    return {type: "map", data: resultData};
  },
  // End intersection/2
  // Deps: []

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
