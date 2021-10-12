"use strict";

import {attributesModule, eventListenersModule, h, init, toVNode} from "snabbdom";
const patch = init([attributesModule, eventListenersModule]);

import ClickEvent from "./events/click_event"
import Runtime from "./runtime"
import Utils from "./utils"

export default class DOM {
  static PRUNED_ATTRS = ["on_click"]

  // TODO: refactor & test
  constructor(runtime, window) {
    this.document = window.document
    this.oldVNode = null
    this.runtime = runtime
    this.window = window
  }

  static buildComponentState(props, state) {
    return Object.keys(props).reduce((acc, key) => {
      acc.data[`~atom[${key}]`] = DOM.evaluateProp(props[key], state)
      return acc
    }, {type: "map", data: {"~atom[context]": state.data["~atom[context]"]}})
  }

  static evaluateNode(node, state) {
    switch (node.type) {
      case "text":
        return {type: "string", value: node.content}

      case "expression":
        return node.callback(state).data[0]
    }
  }

  static evaluateProp(nodes, state) {
    if (nodes.length == 1) {
      return DOM.evaluateNode(nodes[0], state)
    } else {
      return nodes.reduce((acc, node) => {
        return acc + Runtime.interpolate(DOM.evaluateNode(node, state))
      }, "")
    }
  }

  buildVNode(node, fullState, scopeState, context) {
    if (Array.isArray(node)) {
      return node.reduce((acc, n) => {
        acc.push(...this.buildVNode(n, fullState, scopeState, context))
        return acc
      }, [])
    }

    switch (node.type) {
      case "component":
        let module = Runtime.getModule(node.module)

        if (DOM.hasActionHandlers(module)) {
          context = Object.assign({}, context)
          context.scopeModule = module
        }

        context = Utils.clone(context)
        context.slots = { default: node.children }

        let componentState = DOM.buildComponentState(node.props, scopeState)
        return this.buildVNode(module.template(), fullState, componentState, context)

      case "element":
        if (node.tag == "slot") {
          return this.buildVNode(context.slots.default, fullState, scopeState, context)
        }

        let children = node.children.reduce((acc, child) => {
          acc.push(...this.buildVNode(child, fullState, scopeState, context))
          return acc
        }, [])

        let event_handlers = this.buildVNodeEventHandlers(node, fullState, scopeState, context)
        let attrs = DOM.buildVNodeAttrs(node, scopeState)

        return [h(node.tag, {attrs: attrs, on: event_handlers}, children)]

      case "expression":
        const evaluatedExpression = node.callback(scopeState).data[0]
        return [Runtime.interpolate(evaluatedExpression)]

      case "text":
        return [node.content]
    } 
  }

  static buildVNodeAttrs(node, scopeState) {
    return Object.keys(node.attrs).reduce((acc, key) => {
      if (!DOM.PRUNED_ATTRS.includes(key)) {
        let value = node.attrs[key].value
        acc[key] = DOM.evaluateAttributeValue(value, scopeState)         
      }
      return acc
    }, {})
  }

  // TODO: refactor & test
  // DEFER: research whether this creates a new handler on each render (how to optimize it?)
  buildVNodeEventHandlers(node, fullState, scopeState, context) {
    const eventHandlers = {}

    if (node.attrs.on_click) {
      eventHandlers.click = (event) => { Runtime.handleEvent(event, ClickEvent, context.source, node.attrs.on_click) }
    }

    // TODO: implement
    // if (node.attrs.on_submit) {
    //   eventHandlers.submit = this.runtime.handleSubmitEvent.bind(this.runtime, node.attrs.on_submit, fullState, scopeState, context)
    // }

    return eventHandlers
  }

  static evaluateAttributeValue(value, scopeState) {
    return value.reduce((acc, part) => {
      return acc + DOM.evaluateAttributeValuePart(part, scopeState)
    }, "")
  }

  static evaluateAttributeValuePart(value, scopeState) {
    if (value.type == "expression") {
      const result = value.callback(scopeState).data[0]
      return Runtime.interpolate(result)

    } else {
      return value.content
    }
  }

  // TODO: already refactored; test
  getHTML() {
    const doctype = new XMLSerializer().serializeToString(this.document.doctype)
    const outerHTML = this.document.documentElement.outerHTML
    return doctype + outerHTML;
  }

  // TODO: already refactored; test
  static hasActionHandlers(module) {
    return module.hasOwnProperty("action")
  }

  // TODO: refactor & test
  render(pageModule) {
    if (!this.oldVNode) {
      this.oldVNode = toVNode(this.document.documentElement)
    }

    const pageTemplate = pageModule.template()
    const layoutClassName = pageModule.layout().className
    const layoutTemplate = Runtime.getModule(layoutClassName).template()

    const context = {scopeModule: pageModule, pageModule: pageModule, slots: {default: pageTemplate}}

    let newVNode = this.buildVNode(layoutTemplate, this.runtime.state, this.runtime.state, context)[0]
    patch(this.oldVNode, newVNode)
    this.oldVNode = newVNode
  }

  // TODO: refactor & test
  reset() {
    this.oldVNode = null
  }
}