"use strict";

import HologramNotImplementedError from "./errors";
import Utils from "./utils"

export default class Type {
  static atom(value) {
    return Utils.freeze({type: "atom", value: value})
  }

  static atomKey(key) {
    return `~atom[${key}]`
  }

  static boolean(value) {
    return Utils.freeze({type: "boolean", value: value})
  }

  static integer(value) {
    return Utils.freeze({type: "integer", value: value})
  }

  static isFalse(boxedValue) {
    return boxedValue.type === "boolean" && boxedValue.value === false
  }

  static isFalsy(boxedValue) {
    return Type.isFalse(boxedValue) || Type.isNil(boxedValue)
  }

  static isNil(boxedValue) {
    return boxedValue.type === "nil"
  }

  static isNumber(boxedValue) {
    return boxedValue.type === "float" || boxedValue.type === "integer"
  }

  static isTrue(boxedValue) {
    return boxedValue.type === "boolean" && boxedValue.value === true
  }

  static isTruthy(boxedValue) {
    return !Type.isFalsy(boxedValue)
  }

  static keywordToMap(keyword) {
    const result = keyword.data.reduce((acc, elem) => {
      const key = Type.mapKey(elem.data[0])
      acc.data[key] = elem.data[1]
      return acc
    }, {type: "map", data: {}})

    return Utils.freeze(result)
  }

  static list(elems) {
    return Utils.freeze({type: "list", data: elems})
  }

  static map(elems) {
    return Utils.freeze({type: "map", data: elems})
  }

  static mapKey(boxedValue) {
    switch (boxedValue.type) {
      case "atom":
        return `~atom[${boxedValue.value}]`

      case "string":
        return `~string[${boxedValue.value}]`
        
      default:
        const message = `Type.mapKey(): boxedValue = ${JSON.stringify(boxedValue)}`
        throw new HologramNotImplementedError(message)
    }
  }

  static module(className) {
    return Utils.freeze({type: "module", class_name: className})
  }

  static string(value) {
    return Utils.freeze({type: "string", value: value})
  }
}