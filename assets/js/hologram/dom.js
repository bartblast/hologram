"use strict";

import { HologramNotImplementedError } from "./errors";

import {attributesModule, eventListenersModule, h, init, toVNode} from "snabbdom";
const patch = init([attributesModule, eventListenersModule]);

export default class DOM {
  static PRUNED_ATTRS = ["on_click"]

  // TODO: finish & test
  static buildVNode(node) {
    switch (node.type) {
      case "text":
        return DOM.buildTextVNode(node)
    }
  }

  static buildTextVNode(node) {
    return [node.content]
  }

  static interpolate(value) {
    switch (value.type) {
      case "atom":
      case "boolean":
      case "integer":
      case "string":
        return `${value.value}`

      case "binary":
        return value.data.map((elem) => elem.value).join("")

      case "nil":
        return ""

      default:
        const message = `DOM.interpolate(): value = ${JSON.stringify(value)}`
        throw new HologramNotImplementedError(message)
    }
  }
}