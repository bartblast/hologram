"use strict";

import Type from "../type";
import Utils from "../utils"

export default class Map {
  static put(map, key, value) {
    let newMap = Utils.clone(map)
    newMap.data[Type.serializedKey(key)] = value

    return Utils.freeze(newMap);
  }
}