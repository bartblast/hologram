"use strict";

import { HologramNotImplementedError } from "./errors";
import Runtime from "./runtime";
import Utils from "./utils";

import ClickEvent from "./events/click_event";

import {attributesModule, eventListenersModule, h, init, toVNode} from "snabbdom";
const patch = init([attributesModule, eventListenersModule]);

export default class DOM {
  static PRUNED_ATTRS = ["on_click"]

  static buildTextVNode(node) {
    return [node.content]
  }

  // TODO: finish & test
  static buildVNode(node) {
    switch (node.type) {
      case "text":
        return DOM.buildTextVNode(node)
    }
  }

  static buildVNodeEventHandlers(node, source, bindings) {
    const eventHandlers = {}

    if (node.attrs.on_click) {
      eventHandlers.click = (event) => { Runtime.handleEvent(event, ClickEvent, source, bindings, node.attrs.on_click) }
    }

    return eventHandlers
  }

  static evaluateNode(node, bindings) {
    switch (node.type) {
      case "expression":
        return Utils.freeze(node.callback(bindings).data[0])

      case "text":
        return Utils.freeze({type: "string", value: node.content})
    }
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