// DEFER: refactor & test

import Client from "./client"
import DOM from "./dom"

export default class Runtime {
  constructor() {
    this.client = new Client()
    this.dom = new DOM()
    this.pageModule = null
    this.state = null
  }

  handleClickEvent(context, action, state, _event) {
    let actionResult = context.scopeModule.action({ type: "atom", value: action }, {}, state)

    if (actionResult.type == "tuple") {
      this.state = actionResult.data[0]
    } else {
      this.state = actionResult
    }

    this.dom.render(this, context.pageModule)
  }

  restart(pageModule, state) {
    this.pageModule = pageModule
    this.state = state

    this.dom.render(this, this.pageModule)
  }
}