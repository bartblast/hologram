"use strict";

import Map from "../elixir/map"
import Type from "../type"

export default class SubmitEvent {
  // TODO: test
  static buildEventData(event) {
    const formData = new FormData(event.target)
    let params = Type.map()

    for (let el of formData.entries()) {
      params = Map.put(params, Type.atom(el[0]), Type.string(el[1]))
    }

    return params
  }
}