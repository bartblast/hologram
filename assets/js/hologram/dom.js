"use strict";

import { HologramNotImplementedError } from "./errors";
import Runtime from "./runtime";
import Utils from "./utils";

import ClickEvent from "./events/click_event";

import { attributesModule, eventListenersModule, h, init, toVNode } from "snabbdom";
const patch = init([attributesModule, eventListenersModule]);

export default class DOM {
  static PRUNED_ATTRS = ["on_click"]

  static buildElementVNode(node, source, bindings, slots) {
    if (node.tag === "slot") {
      return DOM.buildVNodeList(slots.default, source, bindings, slots)
    }

    let attrs = DOM.buildVNodeAttrs(node, bindings)
    let eventHandlers = DOM.buildVNodeEventHandlers(node, source, bindings)
    let children = DOM.buildVNodeList(node.children, source, bindings, slots)

    return [h(node.tag, {attrs: attrs, on: eventHandlers}, children)]
  }

  static buildTextVNode(node) {
    return [node.content]
  }

  // TODO: finish & test
  static buildVNode(node, source, bindings, slots) {
    if (Array.isArray(node)) {
      return DOM.buildVNodeList(node, source, bindings, slots)
    }

    switch (node.type) {
      case "element":
        return DOM.buildElementVNode(node, source, bindings, slots)

      case "text":
        return DOM.buildTextVNode(node)
    }
  }

  static buildVNodeAttrs(node, bindings) {
    return Object.keys(node.attrs).reduce((acc, key) => {
      if (!DOM.PRUNED_ATTRS.includes(key)) {
        let valueNodes = node.attrs[key].value
        acc[key] = DOM.evaluateAttr(valueNodes, bindings)         
      }
      return acc
    }, {})
  }

  static buildVNodeEventHandlers(node, source, bindings) {
    const eventHandlers = {}

    if (node.attrs.on_click) {
      eventHandlers.click = (event) => { Runtime.handleEvent(event, ClickEvent, source, bindings, node.attrs.on_click) }
    }

    return eventHandlers
  }

  static buildVNodeList(nodes, source, bindings, slots) {
    return nodes.reduce((acc, node) => {
      acc.push(...DOM.buildVNode(node, source, bindings, slots))
      return acc
    }, [])
  }

  static evaluateAttr(nodes, bindings) {
    return nodes.reduce((acc, node) => {
      return acc + DOM.interpolate(DOM.evaluateNode(node, bindings))
    }, "")
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