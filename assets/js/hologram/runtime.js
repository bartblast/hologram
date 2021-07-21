import Client from "./client"
import DOM from "./dom"

export default class Runtime {
  // TODO: refactor & test
  constructor() {
    this.client = new Client(this)
    this.client.connect()

    this.dom = new DOM(this)
    this.pageModule = null
    this.state = null
  }

  // TODO: refactor & test
  executeAction(action, params, state, context) {
    const actionResult = context.scopeModule.action({ type: "atom", value: action }, params, state)

    if (actionResult.type == "tuple") {
      this.state = actionResult.data[0]

      let params = {}
      if (actionResult.data[2]) {
        params = actionResult.data[2]
      }

      this.client.pushCommand(actionResult.data[1].value, context, params)
    } else {
      this.state = actionResult
    }

    this.dom.render(context.pageModule)
  }

  // TODO: refactor & test
  handleClickEvent(context, action, state, _event) {
    this.executeAction(action, {}, state, context)
  }

  // TODO: refactor & test
  handleCommandResponse(response) {
    const action = response[0]
    const params = response[1]

    // TODO: return context in command response
    const context = {pageModule: this.pageModule, scopeModule: this.pageModule}

    this.executeAction(action, {}, this.state, context)
  }

  // TODO: refactor & test
  handleNewPage(pageModule, state) {
    this.pageModule = pageModule
    this.state = state

    this.dom.render(this.pageModule)
  }

  // TODO: refactor & test
  handleSubmitEvent(context, action, state, event) {
    event.preventDefault()

    let formData = new FormData(event.target)
    let params = {type: 'map', data: {}}

    for (var el of formData.entries()) {
      params.data[`~string[${el[0]}]`] = {type: "string", value: el[1]}
    }

    this.executeAction(action, params, state, context)
  }
}