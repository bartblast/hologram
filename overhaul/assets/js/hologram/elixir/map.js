"use strict";

import Type from "../type";
import Utils from "../utils"

export default class Map {
  static put(map, key, value) {
    let newMap = Utils.clone(map)
    newMap.data[Type.encodedKey(key)] = value

    return Utils.freeze(newMap);
  }

  static to_list(map) {
    const data = Object.keys(map.data).reduce((acc, encodedKey) => {
      const key = Type.decodeKey(encodedKey)
      const value = map.data[encodedKey]
      acc.push(Type.tuple([key, value]))
      return acc
    }, [])

    return Type.list(data)
  }
}