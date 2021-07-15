// TODO: refactor & test

import Hologram from "../hologram"

export default class EventHandler {
  static handleClickEvent(context, action, state, runtime, _event) {
    let actionResult = context.scopeModule.action({ type: "atom", value: action }, {}, state)

    if (actionResult.type == "tuple") {
      runtime.state = actionResult.data[0]
    } else {
      runtime.state = actionResult
    }

    Hologram.render(window.prev_vnode, context, runtime)
  }
}