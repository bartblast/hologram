// TODO: refactor & test

// see: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import cloneDeep from "lodash/cloneDeep";

import {attributesModule, eventListenersModule, h, init, toVNode} from "snabbdom";
const patch = init([eventListenersModule, attributesModule]);

import EventHandler from "./event_handler"
import Hologram from "../hologram"

export default class DOM {
  static buildVNode(node, state, context) {
    if (Array.isArray(node)) {
      return node.reduce((acc, n) => {
        acc.push(...DOM.buildVNode(n, state, context))
        return acc
      }, [])
    }

    switch (node.type) {
      case "component":
        let module = Hologram.get_module(node.module)

        if (module.hasOwnProperty("action")) {
          context = Object.assign({}, context)
          context.scopeModule = module
        }

        return DOM.buildVNode(node.children, state, context)

      case "element":
        let children = node.children.reduce((acc, child) => {
          acc.push(...DOM.buildVNode(child, state, context))
          return acc
        }, [])

        let event_handlers = DOM.buildVNodeEventHandlers(node, state, context)
        let attrs = DOM.buildVNodeAttrs(node)

        return [h(node.tag, {attrs: attrs, on: event_handlers}, children)]

      case "expression":
        return [Hologram.evaluate(node.callback(state))]

      case "text":
        return [node.content]
    } 
  }

  static buildVNodeAttrs(node) {
    const attrs = Object.assign({}, node.attrs)
    delete attrs.on_click
    return attrs
  }

  static buildVNodeEventHandlers(node, state, context) {
    const eventHandlers = {}

    if (node.attrs.on_click) {
      eventHandlers.click = EventHandler.handleClickEvent.bind(null, context, node.attrs.on_click, state)
    }

    return eventHandlers
  }
}