"use strict";

import Map from "../elixir/map"
import Type from "../type"

export default class ChangeEvent {
  // DEFER: test
  static buildEventData(event, tag) {
    if (tag === "form") {
      return ChangeEvent.buildFormEventData(event)

    } else {
      // DEFER: implement
      return Type.map()
    }
  }

  // DEFER: test
  static buildFormEventData(event) {
    const formData = new FormData(event.target.form)
    let params = Type.map()

    for (let el of formData.entries()) {
      params = Map.put(params, Type.atom(el[0]), Type.string(el[1]))
    }

    return params
  }

  // DEFER: test
  static shouldHandleEvent(_event) {
    return true
  }
}