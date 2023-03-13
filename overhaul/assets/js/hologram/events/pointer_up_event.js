"use strict";

import Type from "../type"

export default class PointerUpEvent {
  // TODO: implement & test (return boxed map)
  static buildEventData(_event, _tag) {
    return Type.map()
  }

  // DEFER: test
  static shouldHandleEvent(_event) {
    return true
  }
}