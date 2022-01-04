"use strict";

import Type from "../type"
import Utils from "../utils"

export default class PointerDownEvent {
  // TODO: implement & test (return boxed map)
  static buildEventData(_event, _tag) {
    return Utils.freeze(Type.map())
  }

  // DEFER: test
  static shouldHandleEvent(_event) {
    return true
  }
}