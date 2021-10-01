"use strict";

import Client from "./client"
import DOM from "./dom"
import ScriptsReloader from "./scripts_reloader"
import Type from "./type"
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
  
  static evaluateActionOrCommandSpec(eventSpec, scopeState) {
    const eventValueFirstPart = eventSpec.value[0]
    let name, params, target

    if (eventValueFirstPart.type == "expression") {
      const callbackResult = eventValueFirstPart.callback(scopeState)

      if (eventSpec.modifiers.includes("forward")) {
        target = callbackResult.data[0]
        name = callbackResult.data[1]
        params = Type.keywordToMap(callbackResult.data[2])
      } else {
        target = {type: "atom", value: "page"}
        name = callbackResult.data[0]
        params = Type.keywordToMap(callbackResult.data[1])
      }

    // type = text
    } else {
      target = "page"
      name = {type: "atom", value: eventValueFirstPart.content}
      params = {type: "map", data: {}}
    }

    return [target, name, params]
  }

  executeAction(actionTarget, actionName, actionParams, fullState, scopeState, context) {
    let module, state;
    let isPageTarget = actionTarget.type == "atom" && actionTarget.value == "page"

    if (isPageTarget) {
      module = context.pageModule
      state = fullState
    } else {
      module = context.scopeModule
      state = scopeState
    }

    const actionResult = module.action(actionName, actionParams, state)

    if (actionResult.type == "tuple") {
      this.state = actionResult.data[0]

      let commandName = {type: "atom", value: actionResult.data[1].value}

      let commandParams = {type: "map", data: {}}
      if (actionResult.data[2]) {
        commandParams = actionResult.data[2]
      }

      this.client.pushCommand(commandName, commandParams, context)

    } else {
      if (isPageTarget) {
        this.state = actionResult
      } else {
        // TODO: handle non-page targets
      }
    }

    this.dom.render(context.pageModule)
  }

  // TODO: refactor & test
  static getModule(module) {
    let name;

    if (module.type == "module") {
      name = module.class
    } else {
      name = module
    }

    return Utils.eval(name.replace(/\./g, ""))
  }  

  // TODO: refactor & test
  handleClickEvent(onClickSpec, fullState, scopeState, context, event) {
    event.preventDefault()

    if (onClickSpec.modifiers.includes("command")) {
      return this.handleEventCommand(onClickSpec, fullState, scopeState, context)

    } else {
      return this.handleEventAction(onClickSpec, fullState, scopeState, context)
    }
  }

  // Covered by E2E tests.
  handleCommandResponse(response) {
    response = Utils.eval(response)
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

  handleEventAction(eventSpec, fullState, scopeState, context) {
    let actionName, actionParams, actionTarget;
    [actionTarget, actionName, actionParams] = Runtime.evaluateActionOrCommandSpec(eventSpec, scopeState)

    this.executeAction(actionTarget, actionName, actionParams, fullState, scopeState, context)
  }

  handleEventCommand(eventSpec, fullState, scopeState, context) {
    let commandName, commandParams, commandTarget;
    [commandTarget, commandName, commandParams] = Runtime.evaluateActionOrCommandSpec(eventSpec, scopeState)

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
  handleSubmitEvent(onSubmitSpec, fullState, scopeState, context, event) {
    event.preventDefault()

    let formData = new FormData(event.target)
    let params = {type: 'map', data: {}}

    for (var el of formData.entries()) {
      params.data[`~string[${el[0]}]`] = {type: "string", value: el[1]}
    }

    this.executeAction(onSubmitSpec.value, params, fullState, scopeState, context)
  }

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
  mountPage(pageModule, serializedState) {
    this.state = Utils.eval(serializedState)
    this.state.data["~atom[context]"].data['~atom[__state__]'] = {type: "string", value: serializedState}

    this.pageModule = pageModule
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