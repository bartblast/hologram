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

  static expressionNode(callback) {
    return Utils.freeze({type: "expression", callback: callback})
  }

  static float(value) {
    return Utils.freeze({type: "float", value: value})
  }

  static integer(value) {
    return Utils.freeze({type: "integer", value: value})
  }

  static isAtom(boxedValue) {
    return boxedValue.type === "atom"
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

  static isString(boxedValue) {
    return boxedValue.type === "string"
  }

  static isTrue(boxedValue) {
    return boxedValue.type === "boolean" && boxedValue.value === true
  }

  static isTruthy(boxedValue) {
    return !Type.isFalsy(boxedValue)
  }

  static keywordToMap(keyword) {
    const result = keyword.data.reduce((acc, elem) => {
      const key = Type.serializedKey(elem.data[0])
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

  static module(className) {
    return Utils.freeze({type: "module", className: className})
  }

  static nil() {
    return Utils.freeze({type: "nil"})
  }

  static placeholder() {
    return Utils.freeze({type: "placeholder"})
  }

  static serializedKey(boxedValue) {
    switch (boxedValue.type) {
      case "atom":
        return Type.atomKey(boxedValue.value)

      case "string":
        return Type.stringKey(boxedValue.value)
        
      default:
        const message = `Type.serializedKey(): boxedValue = ${JSON.stringify(boxedValue)}`
        throw new HologramNotImplementedError(message)
    }
  }

  static string(value) {
    return Utils.freeze({type: "string", value: value})
  }

  static stringKey(key) {
    return `~string[${key}]`
  }

  static textNode(content) {
    return Utils.freeze({type: "text", content: content})
  }

  static tuple(elems) {
    return Utils.freeze({type: "tuple", data: elems})
  }
}