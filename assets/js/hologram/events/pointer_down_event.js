"use strict";

import Map from "../elixir/map"
import Type from "../type"

export default class PointerDownEvent {
  // DEFER: finish & test
  static buildEventData(event, _tag) {
    return Map.put(Type.map(), Type.atom("pointer_type"), Type.atom(event.pointerType))
  }

  // DEFER: test
  static shouldHandleEvent(_event) {
    return true
  }
}