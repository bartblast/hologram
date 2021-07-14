// TODO: refactor

import EventHandler from "./event_handler"

export default class DOM {
  static buildVNodeEventHandlers(node, state, context) {
    const eventHandlers = {}

    if (node.attrs.on_click) {
      eventHandlers.click = EventHandler.handleClickEvent.bind(null, context, node.attrs.on_click, state)
    }

    return eventHandlers
  }
}