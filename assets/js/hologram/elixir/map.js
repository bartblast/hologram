import Utils from "../utils"

export default class Map {
  static put(map, key, value) {
    let newMap = Utils.clone(map)
    newMap.data[Utils.serialize(key)] = value

    return newMap;
  }
}