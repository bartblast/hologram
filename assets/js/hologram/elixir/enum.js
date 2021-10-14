"use strict";

// see: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import isEqual from "lodash/isEqual";

import { HologramNotImplementedError } from "../errors";
import Type from "../type";

export default class Enum {
  static member$question(enumerable, elem) {
    switch (enumerable.type) {
      case "list":
        if (enumerable.data.find(el => isEqual(el, elem))) {
          return Type.boolean(true)
        } else {
          return Type.boolean(false)
        }

      default: 
        const message = `Enum.member$question(): enumerable = ${JSON.stringify(enumerable)}, elem = ${JSON.stringify(elem)}`
        throw new HologramNotImplementedError(message)
    }
  }
}