"use strict";

import Kernel from "./elixir/kernel";
import Map from "./elixir/map";

import Runtime from "./runtime";
import Store from "./store";
import Target from "./target";
import Type from "./type";
import Utils from "./utils";

import BlurEvent from "./events/blur_event";
import ChangeEvent from "./events/change_event";
import ClickEvent from "./events/click_event";
import PointerDownEvent from "./events/pointer_down_event";
import PointerUpEvent from "./events/pointer_up_event";
import SubmitEvent from "./events/submit_event";
import TransitionEndEvent from "./events/transition_end_event";

import { attributesModule, eventListenersModule, h, init, toVNode } from "snabbdom";
const patch = init([attributesModule, eventListenersModule]);

export default class VDOM {
  static PRUNED_ATTRS = [
    "if", 
    "on:blur", 
    "on:change", 
    "on:click", 
    "on:pointer_down", 
    "on:pointer_up", 
    "on:submit", 
    "on:transition_end"
  ]

  static virtualDocument = null

  static aggregateComponentBindings(componentId, node, outerBindings) {
    const contextBindings = VDOM.aggregateComponentContextBindings(outerBindings)
    const propsBindings = VDOM.aggregateComponentPropsBindings(node, outerBindings)
    const stateBindings = Store.resolveComponentState(componentId)

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

  static aggregateLayoutBindings() {
    const propsBindings = Store.getPageState()
    const stateBindings = Store.getLayoutState()

    const elems = Object.assign({}, propsBindings.data, stateBindings.data)
    return Type.map(elems)
  }

  static buildElementVNode(node, sourceId, bindings, slots) {
    if (node.tag === "slot") {
      if (sourceId === Target.TYPE.layout) {
        sourceId = Target.TYPE.page
        bindings = Store.getPageState()
      }
      
      return VDOM.buildVNodeList(slots.default, sourceId, bindings, slots)
    }

    if (VDOM.shouldRenderElementVNode(node, bindings)) {
      const attrs = VDOM.buildVNodeAttrs(node, bindings)
      const eventHandlers = VDOM.buildVNodeEventHandlers(node, sourceId, bindings)
      const children = VDOM.buildVNodeList(node.children, sourceId, bindings, slots)
      return [h(node.tag, {attrs: attrs, on: eventHandlers}, children)]

    } else {
      return []
    }
  }

  static buildTextVNodeFromExpression(node, bindings) {
    const evaluatedNode = VDOM.evaluateNode(node, bindings)
    return [VDOM.interpolate(evaluatedNode)]
  }

  static buildTextVNodeFromTextNode(node) {
    return [node.content]
  }

  // Covered implicitely in E2E tests.
  static build(node, sourceId, bindings, slots) {
    if (Array.isArray(node)) {
      return VDOM.buildVNodeList(node, sourceId, bindings, slots)
    }

    switch (node.type) {
      case "component":
        return VDOM.buildComponentVNodes(node, sourceId, bindings)

      case "element":
        return VDOM.buildElementVNode(node, sourceId, bindings, slots)

      case "expression":
        return VDOM.buildTextVNodeFromExpression(node, bindings)

      case "text":
        return VDOM.buildTextVNodeFromTextNode(node)
    }
  }

  static buildComponentVNodes(node, sourceId, outerBindings) {
    const componentId = VDOM.getComponentId(node, outerBindings)
    const componentClass = Runtime.resolveComponentClass(node, componentId)

    if (componentId) {
      sourceId = componentId
    }

    const bindings = VDOM.aggregateComponentBindings(componentId, node, outerBindings)

    const childrenCopy = Utils.clone(node.children)
    const slots = { default: Utils.freeze(childrenCopy) }

    return VDOM.build(componentClass.template(), sourceId, bindings, slots)
  }

  static buildVNodeAttrs(node, bindings) {
    return Object.keys(node.attrs).reduce((acc, key) => {
      if (!VDOM.PRUNED_ATTRS.includes(key)) {
        const valueNodes = node.attrs[key].value

        if (valueNodes) {
          const value = VDOM.evaluateAttrParts(valueNodes, bindings)

          if (Type.isNil(value[0])) {
            acc[key] = true
          } else if (!Type.isFalse(value[0])) {
            acc[key] = VDOM.evaluateAttrToString(value)
          }

        } else {
          acc[key] = true
        }
      }
      return acc
    }, {})
  }

  static buildVNodeEventHandlers(node, sourceId, bindings) {
    const eventHandlers = {}

    if (node.attrs["on:blur"]) {
      eventHandlers.blur = (event) => { Runtime.handleEvent(event, BlurEvent, sourceId, bindings, node.attrs["on:blur"], node.tag) }
    }

    if (node.attrs["on:change"]) {
      eventHandlers.change = (event) => { Runtime.handleEvent(event, ChangeEvent, sourceId, bindings, node.attrs["on:change"], node.tag) }
    }

    if (node.attrs["on:click"]) {
      eventHandlers.click = (event) => { Runtime.handleEvent(event, ClickEvent, sourceId, bindings, node.attrs["on:click"], node.tag) }
    }

    if (node.attrs["on:pointer_down"]) {
      eventHandlers.pointerdown = (event) => { Runtime.handleEvent(event, PointerDownEvent, sourceId, bindings, node.attrs["on:pointer_down"], node.tag) }
    }

    if (node.attrs["on:pointer_up"]) {
      eventHandlers.pointerup = (event) => { Runtime.handleEvent(event, PointerUpEvent, sourceId, bindings, node.attrs["on:pointer_up"], node.tag) }
    }

    if (node.attrs["on:submit"]) {
      eventHandlers.submit = (event) => { Runtime.handleEvent(event, SubmitEvent, sourceId, bindings, node.attrs["on:submit"], node.tag) }
    }

    if (node.attrs["on:transition_end"]) {
      eventHandlers.transitionend = (event) => { Runtime.handleEvent(event, TransitionEndEvent, sourceId, bindings, node.attrs["on:transition_end"], node.tag) }
    }

    return eventHandlers
  }

  static buildVNodeList(nodes, sourceId, bindings, slots) {
    nodes = VDOM._convertExpressionNodesToTextNodes(nodes, bindings)
    nodes = VDOM._mergeConsecutiveTextNodes(nodes)

    return nodes.reduce((acc, node) => {
      acc.push(...VDOM.build(node, sourceId, bindings, slots))
      return acc
    }, [])
  }

  // DEFER: test
  static _convertExpressionNodesToTextNodes(nodes, bindings) {
    return nodes.map((node) => {
      if (node.type === "expression") {
        const evaluatedNode = VDOM.evaluateNode(node, bindings)
        const content = VDOM.interpolate(evaluatedNode)
        return Type.textNode(content)
      } else {
        return node
      }
    })
  }

  // DEFER: test
  static _mergeConsecutiveTextNodes(nodes) {
    const mergedNodes = []

    for (const node of nodes) {
      if (node.type === "text" && mergedNodes.length > 0) {
        const prevNode = mergedNodes[mergedNodes.length - 1]

        if (prevNode.type === "text") {
          const mergedNode = Type.textNode(prevNode.content + node.content)
          mergedNodes[mergedNodes.length - 1] = mergedNode
          continue;
        }
      }

      mergedNodes.push(node)
    }

    return mergedNodes
  }

  static evaluateAttrParts(nodes, bindings) {
    return nodes.map(node => VDOM.evaluateNode(node, bindings))
  }

  // DEFER: use bindings
  static evaluateAttrToString(nodes, _bindings) {
    return nodes.map(node => VDOM.interpolate(node)).join("")
  }

  static evaluateNode(node, bindings) {
    bindings = Map.put(bindings, Type.atom("bindings"), bindings)

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
    if (VDOM.isStatefulComponent(node)) {
      const boxedId = VDOM.evaluateProp(node.props.id, bindings)
      return VDOM.interpolate(boxedId)

    } else {
      return null
    }
  }

  // DEFER: test
  static getDocumentHTML(document) {
    const doctype = new XMLSerializer().serializeToString(document.doctype)
    const outerHTML = document.documentElement.outerHTML
    return doctype + outerHTML;
  }

  static interpolate(boxedValue) {
    if (Type.isList(boxedValue)) {
      return `[${boxedValue.data.map(item => VDOM.interpolate(item)).join(", ")}]`
    } 
    
    return Kernel.to_string(boxedValue).value
  }

  static isStatefulComponent(node) {
    return node.props.hasOwnProperty("id")
  }

  // Covered implicitely in E2E tests.
  static render() {
    if (!VDOM.virtualDocument) {
      VDOM.virtualDocument = toVNode(Runtime.document.documentElement)
    }

    const layoutTemplate = Runtime.getLayoutTemplate()
    const slots = {default: Runtime.getPageTemplate()}
    const sourceId = Target.TYPE.layout
    const bindings = VDOM.aggregateLayoutBindings()

    const newVirtualDocument = VDOM.build(layoutTemplate, sourceId, bindings, slots)[0]
    patch(VDOM.virtualDocument, newVirtualDocument)
    VDOM.virtualDocument = newVirtualDocument
  }

  static reset() {
    VDOM.virtualDocument = null
  }

  static shouldRenderElementVNode(node, bindings) {
    if (node.attrs.if) {
      const ifAttrValue = VDOM.evaluateNode(node.attrs.if.value[0], bindings)
      return Type.isTruthy(ifAttrValue)

    } else {
      return true
    }
  }
}