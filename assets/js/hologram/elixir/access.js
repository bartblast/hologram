"use strict";

import { HologramNotImplementedError } from "../errors";
import Keyword from "../elixir/keyword"
import Map from "../elixir/map"
import Type from "../type";

export default class Access {
  // DEFER: test
  static get(container, key, default_value = Type.nil()) {
    switch (container.type) {
      case "list":
        return Keyword.get(container, key, default_value)

      case "map":
        return Map.get(container, key, default_value)

      default:
        const message = `Access.get(): cointainer = ${JSON.stringify(cointainer)}, key = ${JSON.stringify(key)}, default_value = ${JSON.stringify(default_value)}`
        throw new HologramNotImplementedError(message)
    }
  }
}