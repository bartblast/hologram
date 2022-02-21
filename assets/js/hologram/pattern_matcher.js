"use strict";

import { HologramNotImplementedError } from "./errors";
import Map from "./elixir/map"

export default class PatternMatcher {
  static isFunctionArgsPatternMatched(params, args) {
    if (args.length !== params.length) {
      return false;
    }

    for (let i = 0; i < args.length; ++ i) {
      if (!PatternMatcher.isPatternMatched(params[i], args[i])) {
        return false;
      }
    }

    return true;
  }

  static isMapPatternMatched(left, right) {
    for (const key of Map.keys(left).data) {
      if (Map.has_key$question(right, key)) {
        if (!PatternMatcher.isPatternMatched(Map.get(left, key), Map.get(right, key))) {
          return false
        }
      } else {
        return false
      }
    }

    return true 
  }

  static isPatternMatched(left, right) {
    const lType = left.type;
    const rType = right.type;

    if (lType === "placeholder") {
      return true;
    }

    if (lType !== rType) {
      return false;
    }

    switch (lType) {
      case "atom":
      case "integer":
        return left.value === right.value;

      case "map":
        return PatternMatcher.isMapPatternMatched(left, right)

      case "tuple":
        return PatternMatcher.isTuplePatternMatched(left, right)

      default:
        const message = `PatternMatcher.isPatternMatched(): left = ${JSON.stringify(left)}`
        throw new HologramNotImplementedError(message)
    }
  }

  static isTuplePatternMatched(left, right) {
    if (left.data.length !== right.data.length) {
      return false;
    }

    for (let i = 0; i < left.data.length; ++i) {
      if (!PatternMatcher.isPatternMatched(left.data[i], right.data[i])) {
        return false
      }
    }

    return true
  }
}