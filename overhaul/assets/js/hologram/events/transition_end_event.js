"use strict";

import Type from "../type"

export default class TransitionEndEvent {
  // DEFER: test
  static buildEventData(_event, _tag) {
    return Type.map()
  }

  // DEFER: test
  static shouldHandleEvent(_event) {
    return true
  }
}