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

  // TODO: refactor & test
  handleClickEvent(onClickSpec, state, context, _event) {
    if (onClickSpec.modifiers.includes("command")) {
      return this.handleEventCommand(onClickSpec.value, context)

    } else {
      return this.handleEventAction(onClickSpec.value, state, context)
    }
  }

  handleCommandResponse(response) {
    eval(`response = ${response}`)
    const action = response.data[0]
    const params = response.data[1]

    const context = {
      pageModule: Runtime.get_module(response.data[2].data["~string[page_module]"].value),
      scopeModule: Runtime.get_module(response.data[2].data["~string[scope_module]"].value)
    }

    this.executeAction(action, params, this.state, context)
  }

  handleEventAction(eventValue, state, context) {
    let actionName, actionParams;

    if (eventValue.type == "expression") {
      const callbackResult = eventValue.callback(state)
      actionName = callbackResult.data[0]
      actionParams = Utils.keywordToMap(callbackResult.data[1])
    } else {
      actionName = {type: "atom", value: eventValue}
      actionParams = {type: "map", data: {}}
    }

    this.executeAction(actionName, actionParams, state, context)
  }

  handleEventCommand(eventValue, state, context) {
    let commandName, commandParams;

    if (eventValue.type == "expression") {
      const callbackResult = eventValue.callback(state)
      commandName = callbackResult.data[0]
      commandParams = Utils.keywordToMap(callbackResult.data[1])
    } else {
      commandName = {type: "atom", value: eventValue}
      commandParams = {type: "map", data: {}}
    }

    this.client.pushCommand(commandName, commandParams, context)
  }

  // TODO: refactor & test
  handleNewPage(pageModule, state) {
    this.pageModule = pageModule
    this.state = state

    this.dom.render(this.pageModule)
  }

  // TODO: refactor & test
  handleSubmitEvent(context, onSubmitSpec, state, event) {
    event.preventDefault()

    let formData = new FormData(event.target)
    let params = {type: 'map', data: {}}

    for (var el of formData.entries()) {
      params.data[`~string[${el[0]}]`] = {type: "string", value: el[1]}
    }

    this.executeAction(onSubmitSpec.value, params, state, context)
  }

  // TODO: refactor & test
  static interpolate(value) {
    switch (value.type) {
      case "binary":
        return value.data.map((elem) => elem.value).join("")

      case "integer":
        return `${value.value}`
        
      case "string":
        return `${value.value}`
    }
  }  
}