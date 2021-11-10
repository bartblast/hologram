"use strict";

import { HologramNotImplementedError } from "../errors";
import Map from "./map"
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

  static to_list(enumerable) {
    switch (enumerable.type) {
      case "list":
        return enumerable

      case "map":
        const data = Map.keys(enumerable).data.reduce((acc, key) => {
          acc.push(Type.tuple([key, Map.get(enumerable, key)]))
          return acc
        }, [])
        return Type.list(data)

      default: 
        const message = `Enum.to_list(): enumerable = ${JSON.stringify(enumerable)}`
        throw new HologramNotImplementedError(message)      
    }
  }
}