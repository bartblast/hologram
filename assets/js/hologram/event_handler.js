import Hologram from "../hologram"

export default class EventHandler {
  static handleClickEvent(context, action, state, _event) {
    let actionResult = context.scopeModule.action({ type: "atom", value: action }, {}, state)

    if (actionResult.type == "tuple") {
      window.state = actionResult.data[0]
    } else {
      window.state = actionResult
    }

    Hologram.render(window.prev_vnode, context)
  }
}