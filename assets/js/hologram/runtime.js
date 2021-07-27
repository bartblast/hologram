import Client from "./client"
import DOM from "./dom"
import Utils from "./utils"

export default class Runtime {
  constructor(window) {
    this.client = new Client(this)
    this.client.connect()

    this.dom = new DOM(this, window)
    this.pageModule = null
    this.state = null
  }

  executeAction(actionName, actionParams, state, context) {
    const actionResult = context.scopeModule.action(actionName, actionParams, state)

    if (actionResult.type == "tuple") {
      this.state = actionResult.data[0]

      let commandParams = {type: "map", data: {}}
      if (actionResult.data[2]) {
        commandParams = actionResult.data[2]
      }

      this.client.pushCommand(actionResult.data[1].value, commandParams, context)
    } else {
      this.state = actionResult
    }

    this.dom.render(context.pageModule)
  }

  // TODO: refactor & test
  static get_module(name) {
    return eval(name.replace(/\./g, ""))
  }  

  handleClickEvent(onClickProp, state, context, _event) {
    let actionName, actionParams;

    if (onClickProp.type == "expression") {
      const callbackResult = onClickProp.callback(state)
      actionName = callbackResult.data[0]
      actionParams = Utils.keywordToMap(callbackResult.data[1])
    } else {
      actionName = {type: "atom", value: onClickProp}
      actionParams = {type: "map", data: {}}
    }

    this.executeAction(actionName, actionParams, state, context)
  }

  // TODO: refactor & test
  handleCommandResponse(response) {
    const action = response[0]
    const params = response[1]

    // TODO: return context in command response
    const context = {pageModule: this.pageModule, scopeModule: this.pageModule}

    this.executeAction(action, {type: "map", data: {}}, this.state, context)
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

  // TODO: refactor & test
  static interpolate(value) {
    switch (value.type) {
      case "integer":
        return `${value.value}`
        
      case "string":
        return `${value.value}`
    }
  }  
}