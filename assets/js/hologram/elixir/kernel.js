"use strict";

import { HologramNotImplementedError } from "../errors";
import Map from "../elixir/map"
import Runtime from "../runtime"
import Type from "../type"
import Utils from "../utils"

export default class Kernel {
  static apply() {
    if (arguments.length === 3) {
      const module = Runtime.getClassByClassName(arguments[0].className)
      const functionName = arguments[1].value
      const args = arguments[2].data

      return module[functionName](...args)

    } else {
      const message = `Kernel.apply(): arguments = ${JSON.stringify(arguments)}`
      throw new HologramNotImplementedError(message)
    }
  }

  // TODO: raise ArgumentError when index is negative or it is out of range
  static elem(tuple, index) {
    return tuple.data[index]
  }

  // TODO: raise ArgumentError if the list is empty.
  static hd(list) {
    return list.data[0]
  }

  static if(condition, doClause, elseClause) {
    let result;

    if (Type.isTruthy(condition())) {
      result = doClause()
    } else {
      result = elseClause()
    }

    return Utils.freeze(result)
  }

  static is_function(term) {
    return Type.isAnonymousFunction(term) ? Type.boolean(true) : Type.boolean(false)
  }

  // DEFER: implement other types (works for maps only)
  static put_in(data, keys, value) {
    const key = keys.data[0]

    if (keys.data.length > 1) {
      const subtree = Map.get(data, key)
      const subtreeKeys = Type.list(keys.data.slice(1))
      const newSubtree = Kernel.put_in(subtree, subtreeKeys, value)
      return Map.put(data, key, newSubtree)

    } else {
      return Map.put(data, key, value)
    }
  }

  static $subtract_lists(left, right) {
    const rightElems = Utils.clone(right.data)
    const resultElems = []

    for (let leftElem of left.data) {
      let isLeftElemPreserved = true
      let rightElemIndex = rightElems.findIndex(rightElem => Utils.isEqual(rightElem, leftElem))

      if (rightElemIndex != -1) {
        isLeftElemPreserved = false
        rightElems.splice(rightElemIndex, 1)
      }

      if (isLeftElemPreserved) {
        resultElems.push(leftElem)
      }
    }

    return Type.list(resultElems)
  }

  // TODO: raise ArgumentError if the list is empty.
  static tl(list) {
    return Type.list(list.data.slice(1))
  }

  static to_string(boxedValue) {
    switch (boxedValue.type) {
      case "atom":
      case "boolean":
      case "float":
      case "integer":
        return Type.string(`${boxedValue.value}`)

      case "binary":
        const str = boxedValue.data
          .map(elem => Kernel.to_string(elem).value)
          .join("")

        return Type.string(str)

      case "nil":
        return Type.string("")

      case "string":
        return boxedValue

      default:
        const message = `Kernel.to_string(): boxedValue = ${JSON.stringify(boxedValue)}`
        throw new HologramNotImplementedError(message)
    }
  }

  static $unary_negative(boxedValue) {
    return Utils.freeze({type: boxedValue.type, value: -boxedValue.value})
  }
}