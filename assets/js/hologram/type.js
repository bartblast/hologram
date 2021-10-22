"use strict";

import { HologramNotImplementedError } from "./errors";
import Utils from "./utils"

export default class Type {
  static atom(value) {
    return Utils.freeze({type: "atom", value: value})
  }

  static atomKey(key) {
    return `~atom[${key}]`
  }

  static binary(elems) {
    return Utils.freeze({type: "binary", data: elems})
  }

  static boolean(value) {
    return Utils.freeze({type: "boolean", value: value})
  }

  static componentNode(className, props, children) {
    return Utils.freeze({type: "component", module: className, props: props, children: children})
  }

  static elementNode(tag, attrs, children) {
    return Utils.freeze({type: "element", tag: tag, attrs: attrs, children: children})
  }

  static encodedKey(boxedValue) {
    switch (boxedValue.type) {
      case "atom":
        return Type.atomKey(boxedValue.value)

      case "string":
        return Type.stringKey(boxedValue.value)
        
      default:
        const message = `Type.encodedKey(): boxedValue = ${JSON.stringify(boxedValue)}`
        throw new HologramNotImplementedError(message)
    }
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

  static isExpressionNode(node) {
    return node.type === "expression"
  }

  static isFalse(boxedValue) {
    return boxedValue.type === "boolean" && boxedValue.value === false
  }

  static isFalsy(boxedValue) {
    return Type.isFalse(boxedValue) || Type.isNil(boxedValue)
  }

  static isList(boxedValue) {
    return boxedValue.type === "list"
  }

  static isMap(boxedValue) {
    return boxedValue.type === "map"
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

  static isTuple(boxedValue) {
    return boxedValue.type === "tuple"
  }

  static keywordToMap(keyword) {
    const result = keyword.data.reduce((acc, elem) => {
      const key = Type.encodedKey(elem.data[0])
      acc.data[key] = elem.data[1]
      return acc
    }, {type: "map", data: {}})

    return Utils.freeze(result)
  }

  static list(elems) {
    return Utils.freeze({type: "list", data: elems})
  }

  static map(elems, immutable = true) {
    const result = {type: "map", data: elems}
    return immutable ? Utils.freeze(result) : result
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