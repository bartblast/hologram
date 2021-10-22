"use strict";

import { HologramNotImplementedError } from "../../errors";
import Type from "../../type"

export default class SpecialForms {
  static $dot(boxedMap, boxedKey) {
    return boxedMap.data[Type.encodedKey(boxedKey)]
  }
  
  static $type(value, type) {
    if (Type.isString(value) && type === "binary") {
      return value
    } else {
      const message = `Elixir_Kernel_SpecialForms.$type(): value = ${JSON.stringify(value)}, type = ${JSON.stringify(type)}`
      throw new HologramNotImplementedError(message)
    }
  }
}