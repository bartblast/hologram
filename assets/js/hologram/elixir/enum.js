"use strict";

import { HologramNotImplementedError } from "../errors";
import Type from "../type";
import Utils from "../utils";

export default class Enum {
  static member$question(enumerable, elem) {
    switch (enumerable.type) {
      case "list":
        if (enumerable.data.find(el => Utils.isEqual(el, elem))) {
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