"use strict";

import { HologramNotImplementedError } from "./errors";
import Runtime from "./runtime";
import Store from "./store";
import Utils from "./utils";

import ClickEvent from "./events/click_event";

import { attributesModule, eventListenersModule, h, init, toVNode } from "snabbdom";
import Type from "./type";
const patch = init([attributesModule, eventListenersModule]);

export default class VDOM {
  static PRUNED_ATTRS = ["on_click"]

  static aggregateComponentBindings(node, outerBindings) {
    const contextBindings = VDOM.aggregateComponentContextBindings(outerBindings)
    const propsBindings = VDOM.aggregateComponentPropsBindings(node, outerBindings)
    const stateBindings = VDOM.aggregateComponentStateBindings(node, outerBindings)

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
      acc[Type.atomKey(key)] = VDOM.evaluateProp(node.props[key], outerBindings)
      return acc
    }, {})

    return Type.map(elems)
  }

  static aggregateComponentStateBindings(node, outerBindings) {
    if (VDOM.isStatefulComponent(node)) {
      const componentId = VDOM.getComponentId(node, outerBindings)
      return Store.getComponentState(componentId)

    } else {
      return Utils.freeze({})
    }
  }

  static buildElementVNode(node, source, bindings, slots) {
    if (node.tag === "slot") {
      return VDOM.buildVNodeList(slots.default, source, bindings, slots)
    }

    const attrs = VDOM.buildVNodeAttrs(node, bindings)
    const eventHandlers = VDOM.buildVNodeEventHandlers(node, source, bindings)
    const children = VDOM.buildVNodeList(node.children, source, bindings, slots)

    return [h(node.tag, {attrs: attrs, on: eventHandlers}, children)]
  }

  static buildTextVNodeFromExpression(node, bindings) {
    const evaluatedNode = VDOM.evaluateNode(node, bindings)
    return [VDOM.interpolate(evaluatedNode)]
  }

  static buildTextVNodeFromTextNode(node) {
    return [node.content]
  }

  // TODO: finish & test
  static build(node, source, bindings, slots) {
    if (Array.isArray(node)) {
      return VDOM.buildVNodeList(node, source, bindings, slots)
    }

    switch (node.type) {
      case "component":
        return VDOM.buildComponentVNodes(node, source, bindings)

      case "element":
        return VDOM.buildElementVNode(node, source, bindings, slots)

      case "expression":
        return VDOM.buildTextVNodeFromExpression(node, bindings)

      case "text":
        return VDOM.buildTextVNodeFromTextNode(node)
    }
  }

  static buildComponentVNodes(node, source, outerBindings) {
    if (VDOM.isStatefulComponent(node)) {
      source = VDOM.getComponentId(node, outerBindings)
    }

    const childrenCopy = Utils.clone(node.children)
    const slots = { default: Utils.freeze(childrenCopy) }

    let klass = Runtime.getClassByClassName(node.module)
    const bindings = VDOM.aggregateComponentBindings(node, outerBindings)

    return VDOM.build(klass.template(), source, bindings, slots)
  }

  static buildVNodeAttrs(node, bindings) {
    return Object.keys(node.attrs).reduce((acc, key) => {
      if (!VDOM.PRUNED_ATTRS.includes(key)) {
        let valueNodes = node.attrs[key].value
        acc[key] = VDOM.evaluateAttr(valueNodes, bindings)         
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
      acc.push(...VDOM.build(node, source, bindings, slots))
      return acc
    }, [])
  }

  static evaluateAttr(nodes, bindings) {
    return nodes.reduce((acc, node) => {
      return acc + VDOM.interpolate(VDOM.evaluateNode(node, bindings))
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
      return VDOM.evaluateNode(nodes[0], bindings)

    } else {
      const concatenatedStr = nodes.reduce((acc, node) => {
        const nodeStr = VDOM.interpolate(VDOM.evaluateNode(node, bindings))
        return acc + nodeStr
      }, "")

      return Type.string(concatenatedStr)
    }
  }

  static getComponentId(node, bindings) {
    const boxedId = VDOM.evaluateProp(node.props.id, bindings)
    return VDOM.interpolate(boxedId)
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
        const message = `VDOM.interpolate(): value = ${JSON.stringify(value)}`
        throw new HologramNotImplementedError(message)
    }
  }

  static isStatefulComponent(node) {
    return node.props.hasOwnProperty("id")
  }
}