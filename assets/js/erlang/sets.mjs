"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Erlang_Sets = {
  // Start subtract/2
  "subtract/2": (set1, set2) => {
    if (!Type.isMap(set1)) {
      Interpreter.raiseBadMapError(set1);
    }

    if (!Type.isMap(set2)) {
      Interpreter.raiseBadMapError(set2);
    }

    const resultData = {...set1.data};

    for (const key of Object.keys(set2.data)) {
      delete resultData[key];
    }

    return {type: "map", data: resultData};
  },
  // End subtract/2
  // Deps: []
};

export default Erlang_Sets;
