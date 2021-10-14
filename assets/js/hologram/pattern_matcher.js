"use strict";

import { HologramNotImplementedError } from "./errors";

export default class PatternMatcher {
  static isFunctionArgsPatternMatched(params, args) {
    if (args.length != params.length) {
      return false;
    }

    for (let i = 0; i < args.length; ++ i) {
      if (!PatternMatcher.isPatternMatched(params[i], args[i])) {
        return false;
      }
    }

    return true;
  }

  static isPatternMatched(left, right) {
    let lType = left.type;
    let rType = right.type;

    if (lType === "placeholder") {
      return true;
    }

    if (lType != rType) {
      return false;
    }

    switch (lType) {
      case "atom":
        return left.value === right.value;

      default:
        const message = `PatternMatcher.isPatternMatched(): left = ${JSON.stringify(left)}`
        throw new HologramNotImplementedError(message)
    }
  }
}