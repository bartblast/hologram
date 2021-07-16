// DEFER: refactor & test

import Client from "./client"
import DOM from "./dom"

export default class Runtime {
  constructor() {
    this.client = new Client(this)
    this.client.connect()

    this.dom = new DOM(this)
    this.pageModule = null
    this.state = null
  }

  executeAction(action, params, state, context) {
    const actionResult = context.scopeModule.action({ type: "atom", value: action }, params, state)

    if (actionResult.type == "tuple") {
      this.state = actionResult.data[0]
      this.client.pushCommand(actionResult.data[1].value, context)
    } else {
      this.state = actionResult
    }

    this.dom.render(context.pageModule)
  }

  handleClickEvent(context, action, state, _event) {
    this.executeAction(action, {}, state, context)
  }

  handleCommandResponse(response) {
    const action = response[0]
    const params = response[1]

    // TODO: return context in command response
    const context = {pageModule: this.pageModule, scopeModule: this.pageModule}
    
    this.executeAction(action, {}, this.state, context)
  }

  handleNewPage(pageModule, state) {
    this.pageModule = pageModule
    this.state = state

    this.dom.render(this.pageModule)
  }
}