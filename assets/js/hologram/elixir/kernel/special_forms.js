"use strict";

import { HologramNotImplementedError } from "../../errors";
import Type from "../../type"
import Utils from "../../utils"

export default class SpecialForms {
  static case(exprAnonFun) {
    const result = exprAnonFun()
    return Utils.freeze(result)
  }

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