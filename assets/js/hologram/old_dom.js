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