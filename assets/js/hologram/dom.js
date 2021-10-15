"use strict";

import { HologramNotImplementedError } from "./errors";
import Runtime from "./runtime";
import Store from "./store";
import Utils from "./utils";

import ClickEvent from "./events/click_event";

import { attributesModule, eventListenersModule, h, init, toVNode } from "snabbdom";
import Type from "./type";
const patch = init([attributesModule, eventListenersModule]);

export default class DOM {
  static PRUNED_ATTRS = ["on_click"]

  static aggregateComponentBindings(node, outerBindings) {
    const contextBindings = DOM.aggregateComponentContextBindings(outerBindings)
    const propsBindings = DOM.aggregateComponentPropsBindings(node, outerBindings)
    const stateBindings = DOM.aggregateComponentStateBindings(node, outerBindings)

    const elems = Object.assign({}, contextBindings.data, propsBindings.data, stateBindings.data)
    return Type.map(elems)
  }

  static aggregateComponentContextBindings(outerBindings) {
    const key = Type.atomKey("context")

    let elems = {}
    elems[key] = outerBindings.data[key]

    return Type.map(elems)
  }

  static aggregateComponentPropsBindings(node, outerBindings) {
    const elems = Object.keys(node.props).reduce((acc, key) => {
      acc[Type.atomKey(key)] = DOM.evaluateProp(node.props[key], outerBindings)
      return acc
    }, {})

    return Type.map(elems)
  }

  static aggregateComponentStateBindings(node, outerBindings) {
    if (DOM.isStatefulComponent(node)) {
      const componentId = DOM.getComponentId(node, outerBindings)
      return Store.getComponentState(componentId)

    } else {
      return Utils.freeze({})
    }
  }

  static buildElementVNode(node, source, bindings, slots) {
    if (node.tag === "slot") {
      return DOM.buildVNodeList(slots.default, source, bindings, slots)
    }

    const attrs = DOM.buildVNodeAttrs(node, bindings)
    const eventHandlers = DOM.buildVNodeEventHandlers(node, source, bindings)
    const children = DOM.buildVNodeList(node.children, source, bindings, slots)

    return [h(node.tag, {attrs: attrs, on: eventHandlers}, children)]
  }

  static buildTextVNodeFromExpression(node, bindings) {
    const evaluatedNode = DOM.evaluateNode(node, bindings)
    return [DOM.interpolate(evaluatedNode)]
  }

  static buildTextVNodeFromTextNode(node) {
    return [node.content]
  }

  // TODO: finish & test
  static buildVDOM(node, source, bindings, slots) {
    if (Array.isArray(node)) {
      return DOM.buildVNodeList(node, source, bindings, slots)
    }

    switch (node.type) {
      case "element":
        return DOM.buildElementVNode(node, source, bindings, slots)

      case "expression":
        return DOM.buildTextVNodeFromExpression(node)

      case "text":
        return DOM.buildTextVNodeFromTextNode(node)
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
      acc.push(...DOM.buildVDOM(node, source, bindings, slots))
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

  static evaluateProp(nodes, bindings) {
    if (nodes.length == 1) {
      return DOM.evaluateNode(nodes[0], bindings)

    } else {
      const concatenatedStr = nodes.reduce((acc, node) => {
        const nodeStr = DOM.interpolate(DOM.evaluateNode(node, bindings))
        return acc + nodeStr
      }, "")

      return Type.string(concatenatedStr)
    }
  }

  static getComponentId(node, bindings) {
    const boxedId = DOM.evaluateProp(node.props.id, bindings)
    return DOM.interpolate(boxedId)
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

  static isStatefulComponent(node) {
    return node.props.hasOwnProperty("id")
  }
}