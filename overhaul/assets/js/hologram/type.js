"use strict";

// TODO: test

import { HologramNotImplementedError } from "./errors";
import Utils from "./utils"

export default class Type {
  static anonymousFunction(callback) {
    return Utils.freeze({type: "anonymous_function", callback: callback})
  }

  static atomKey(key) {
    return `~atom[${key}]`
  }

  static binary(elems) {
    return Utils.freeze({type: "binary", data: elems})
  }

  static componentNode(className, props, children) {
    return Utils.freeze({type: "component", className: className, props: props, children: children})
  }

  static consOperatorPattern(head, tail) {
    return Utils.freeze({type: "cons_operator_pattern", head: head, tail: tail})
  }

  static decodeKey(key) {
    const regex = /^~([a-z]+)\[(.*)\]$/
    const matches = regex.exec(key)
    const type = matches[1]
    const value = matches[2]

    switch (type) {
      case "atom":
        return Type.atom(value)

      case "string":
        return Type.string(value)

      default:
        const message = `Type.decodeKey(): key = ${JSON.stringify(key)}`
        throw new HologramNotImplementedError(message)        
    }
  }

  static elementNode(tag, attrs = {}, children = []) {
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

  // DEFER: test
  static expressionNode(callback) {
    return Utils.freeze({type: "expression", callback: callback})
  }

  static isAnonymousFunction(boxedValue) {
    return boxedValue.type === "anonymous_function"
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

  static list(elems = []) {
    return Utils.freeze({type: "list", data: elems})
  }

  static map(elems = {}, immutable = true) {
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

  static struct(className, elems = {}) {
    return Utils.freeze({type: "struct", className: className, data: elems})
  }

  static textNode(content) {
    return Utils.freeze({type: "text", content: content})
  }

  static tuple(elems = []) {
    return Utils.freeze({type: "tuple", data: elems})
  }
}