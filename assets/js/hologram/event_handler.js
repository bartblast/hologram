// TODO: refactor & test

import DOM from "./dom"

export default class EventHandler {
  static handleClickEvent(context, action, state, runtime, dom, _event) {
    let actionResult = context.scopeModule.action({ type: "atom", value: action }, {}, state)

    if (actionResult.type == "tuple") {
      runtime.state = actionResult.data[0]
    } else {
      runtime.state = actionResult
    }

    dom.render(runtime, context.pageModule)
  }
}