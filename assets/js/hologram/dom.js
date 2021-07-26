import {attributesModule, eventListenersModule, h, init, toVNode} from "snabbdom";
const patch = init([attributesModule, eventListenersModule]);

import Runtime from "./runtime"

export default class DOM {
  // TODO: refactor & test
  constructor(runtime, window) {
    this.oldVNode = null
    this.runtime = runtime
    this.window = window
  }

  // TODO: refactor & test
  buildVNode(node, state, context) {
    if (Array.isArray(node)) {
      return node.reduce((acc, n) => {
        acc.push(...this.buildVNode(n, state, context))
        return acc
      }, [])
    }

    switch (node.type) {
      case "component":
        let module = this.runtime.get_module(node.module)

        if (module.hasOwnProperty("action")) {
          context = Object.assign({}, context)
          context.scopeModule = module
        }

        return this.buildVNode(node.children, state, context)

      case "element":
        let children = node.children.reduce((acc, child) => {
          acc.push(...this.buildVNode(child, state, context))
          return acc
        }, [])

        let event_handlers = this.buildVNodeEventHandlers(node, state, context)
        let attrs = DOM.buildVNodeAttrs(node)

        return [h(node.tag, {attrs: attrs, on: event_handlers}, children)]

      case "expression":
        const evaluatedExpression = node.callback(state).data[0]
        return [Runtime.interpolate(evaluatedExpression)]

      case "text":
        return [node.content]
    } 
  }

  // TODO: refactor & test
  static buildVNodeAttrs(node) {
    const attrs = Object.assign({}, node.attrs)
    delete attrs.on_click
    return attrs
  }

  // TODO: refactor & test
  // DEFER: research whether this creates a new handler on each render (how to optimize it?)
  buildVNodeEventHandlers(node, state, context) {
    const eventHandlers = {}

    if (node.attrs.on_click) {
      eventHandlers.click = this.runtime.handleClickEvent.bind(this.runtime, context, node.attrs.on_click, state)
    }

    if (node.attrs.on_submit) {
      eventHandlers.submit = this.runtime.handleSubmitEvent.bind(this.runtime, context, node.attrs.on_submit, state)
    }

    return eventHandlers
  }

  // TODO: refactor & test
  render(pageModule) {
    console.log("rendering with state:")
    console.debug(this.runtime.state)
    if (!this.oldVNode) {
      const container = this.window.document.body
      this.oldVNode = toVNode(container)
    }

    let context = {scopeModule: pageModule, pageModule: pageModule}
    let template = context.pageModule.template()

    let newVNode = this.buildVNode(template, this.runtime.state, context)[0]
    patch(this.oldVNode, newVNode)
    this.oldVNode = newVNode
  }
}