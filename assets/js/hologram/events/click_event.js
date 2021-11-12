"use strict";

import Type from "../type"
import Utils from "../utils"

export default class ClickEvent {
  // TODO: implement & test (return boxed map)
  static buildEventData(_event, _tag) {
    return Utils.freeze(Type.map())
  }
}