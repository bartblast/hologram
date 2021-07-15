// DEFER: refactor & test

import Client from "./client"
import DOM from "./dom"

export default class Runtime {
  constructor() {
    this.client = new Client()
    this.client.connect()

    this.dom = new DOM(this)
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

    this.dom.render(context.pageModule)
  }

  handleNewPage(pageModule, state) {
    this.pageModule = pageModule
    this.state = state

    this.dom.render(this.pageModule)
  }
}