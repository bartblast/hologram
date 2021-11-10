"use strict";

import Type from "../type";
import Utils from "../utils"

export default class Map {
  static get(map, key, default_value = Type.nil()) {
    if (Map.has_key$question(map, key).value) {
      return map.data[Type.encodedKey(key)]
      
    } else {
      return default_value
    }
  }

  static has_key$question(map, key) {
    if (map.data.hasOwnProperty(Type.encodedKey(key))) {
      return Type.boolean(true)

    } else {
      return Type.boolean(false)
    }
  }

  static keys(map) {
    const keysData = Object.keys(map.data).reduce((acc, key) => {
      acc.push(Type.decodeKey(key))
      return acc
    }, [])

    return Type.list(keysData)
  }

  static put(map, key, value) {
    let newMap = Utils.clone(map)
    newMap.data[Type.encodedKey(key)] = value

    return Utils.freeze(newMap);
  }
}