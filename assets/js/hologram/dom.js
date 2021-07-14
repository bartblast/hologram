// TODO: refactor & test

// see: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import cloneDeep from "lodash/cloneDeep";

import EventHandler from "./event_handler"

export default class DOM {
  static buildVNodeAttrs(node) {
    const attrs = cloneDeep(node.attrs)
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