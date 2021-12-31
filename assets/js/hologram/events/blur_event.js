"use strict";

import Type from "../type"
import Utils from "../utils"

export default class BlurEvent {
  static buildEventData(_event, _tag) {
    return Utils.freeze(Type.map())
  }

  // DEFER: test
  static shouldHandleEvent(event) {
    return true
  }
}