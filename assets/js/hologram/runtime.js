import Client from "./client"
import DOM from "./dom"
import ScriptsReloader from "./scripts_reloader"
import Utils from "./utils"

export default class Runtime {
  constructor(window) {
    this.client = new Client(this)
    this.client.connect()

    this.document = window.document
    this.dom = new DOM(this, window)
    this.pageModule = null
    this.state = null
    this.window = window

    this.loadPageOnPopStateEvents()
  }

  executeAction(actionName, actionParams, state, context) {
    const actionResult = context.scopeModule.action(actionName, actionParams, state)

    if (actionResult.type == "tuple") {
      this.state = actionResult.data[0]

      let commandName = {type: "atom", value: actionResult.data[1].value}

      let commandParams = {type: "map", data: {}}
      if (actionResult.data[2]) {
        commandParams = actionResult.data[2]
      }

      this.client.pushCommand(commandName, commandParams, context)

    } else {
      this.state = actionResult
    }

    this.dom.render(context.pageModule)
  }

  // TODO: refactor & test
  static getModule(name) {
    return eval(name.replace(/\./g, ""))
  }  

  // TODO: refactor & test
  handleClickEvent(onClickSpec, state, context, event) {
    event.preventDefault()

    if (onClickSpec.modifiers.includes("command")) {
      return this.handleEventCommand(onClickSpec.value, state, context)

    } else {
      return this.handleEventAction(onClickSpec.value, state, context)
    }
  }

  // Covered by E2E tests.
  handleCommandResponse(response) {
    eval(`response = ${response}`)
    const action = response.data[0]
    const params = response.data[1]

    if (action.value == "__redirect__") {
      this.handleRedirect(params)

    } else {
      const context = {
        pageModule: Runtime.getModule(response.data[2].data["~string[page_module]"].value),
        scopeModule: Runtime.getModule(response.data[2].data["~string[scope_module]"].value)
      }

      this.executeAction(action, params, this.state, context)
    }
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
  handleRedirect(params) {
    const html = params.data["~atom[html]"].value
    this.loadPage(html)

    const url = params.data["~atom[url]"].value
    this.updateURL(url)
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

  // TODO: refactor & test
  loadPage(html) {
    // TODO: copy html node attributes (because only the inner HTML is updated)
    this.document.documentElement.innerHTML = html

    this.dom.reset()
    ScriptsReloader.reload(this.document)
  }

  // TODO: refactor & test
  loadPageOnPopStateEvents() {
    this.window.addEventListener("popstate", event => {
      this.loadPage(event.state)
    })
  }

  // TODO: refactor & test
  mountPage(pageModule, state) {
    this.pageModule = pageModule
    this.state = state
    this.dom.render(this.pageModule)

    const html = this.dom.getHTML()
    // DEFER: consider - there are limitations for state object size, e.g. 2 MB for Firefox
    this.window.history.replaceState(html, null)
  }

  // TODO: refactor & test
  updateURL(url) {
    this.window.history.pushState(null, null, url)
  }
}