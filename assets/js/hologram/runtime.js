"use strict";

import Client from "./client"
import DOM from "./dom"
import ScriptsReloader from "./scripts_reloader"
import Store from "./store";
import Type from "./type"
import Utils from "./utils"

export default class Runtime {
  buildOperation(eventHandlerSpec, context) {
    const node = eventHandlerSpec.value[0];

    if (node.type === "expression") {
      return this.buildOperationFromExpressionNode(node, context)

    } else { // node.type === "text"
      return Runtime.buildOperationFromTextNode(node, context)
    }
  }
  
  buildOperationFromExpressionNode(node, context) {
    const specElems = node.callback(context.bindings).data

    if (Runtime.hasOperationTarget(specElems)) {
      return this.buildOperationFromExpressionNodeWithTarget(specElems, context)
    } else {
      return Runtime.buildOperationFromExpressionNodeWithoutTarget(specElems, context)
    }
  }

  buildOperationFromExpressionNodeWithTarget(specElems, context) {
    let targetModule, targetId;
    const target = specElems[0].value

    switch (target) {
      case "layout":
        targetModule = context.layoutModule
        targetId = null
        break;

      case "page":
        targetModule = context.pageModule
        targetId = null
        break;

      default:
        targetModule = this.getModuleByComponentId(target);
        targetId = target
        break;
    }

    return {
      targetModule: targetModule,
      targetId: targetId,
      name: specElems[1],
      params: Type.keywordToMap(specElems[2])
    }
  }

  static buildOperationFromExpressionNodeWithoutTarget(specElems, context) {
    return {
      targetModule: context.targetModule,
      targetId: context.targetId,
      name: specElems[0],
      params: Type.keywordToMap(specElems[1])
    }
  }

  static buildOperationFromTextNode(textNode, context) {
    return {
      targetModule: context.targetModule,
      targetId: null,
      name: Type.atom(textNode.content),
      params: Type.map({})
    }
  }

  executeAction(actionSpec, context) {
    const operation = this.buildOperation(actionSpec, context)
    const actionResult = operation.targetModule.action(operation.name, operation.params, context.state)

    let newState;
    let commandName = null
    let commandParams = null

    if (Type.isTuple(actionResult)) {
      const actionResultElems = actionResult.data
      newState = actionResultElems[0]

      if (actionResultElems.length > 1) {
        commandName = actionResultElems[1]
      }

      if (actionResultElems.length > 2) {
        commandParams = actionResultElems[2]
      } else if (actionResultElems.length > 1) {
        commandParams = Type.list([])
      }

    } else {
      newState = actionResult
    }

    return {
      newState: newState,
      commandName: commandName,
      commandParams: commandParams
    }
  }

  static getInstance(window) {
    if (!window.__hologramRuntime__) {
      window.__hologramRuntime__ = new Runtime(window)
    }

    return window.__hologramRuntime__
  }

  getModuleByComponentId(componentId) {
    return this.componentModules[componentId]
  }

  static getCommandNameFromActionResult(actionResult) {
    if (Type.isMap(actionResult)) {
      return null

    } else { // tuple
      const actionResultElems = actionResult.data
 
      if (actionResultElems.length >= 3 && Type.isAtom(actionResultElems[2])) {
        return actionResultElems[2]

      } else if (actionResultElems.length >= 2) {
        return actionResultElems[1]

      } else {
        return null
      }
    }
  }

  static getStateFromActionResult(actionResult) {
    if (Type.isMap(actionResult)) {
      return actionResult

    } else { // tuple
      return actionResult.data[0]
    }
  }

  static getTargetFromActionResult(actionResult) {
    if (Type.isMap(actionResult)) {
      return null

    } else { // tuple
      const actionResultElems = actionResult.data

      if (actionResultElems.length >= 3 && Type.isAtom(actionResultElems[2])) {
        return actionResultElems[1]        

      } else {
        return null
      }
    }
  }

  static hasOperationTarget(specElems) {
    return specElems.length >= 2 && Type.isAtom(specElems[0]) && Type.isAtom(specElems[1])
  }



















  




  constructor(window) {
    this.client = new Client()
    this.client.connect()

    this.document = window.document
    this.dom = new DOM(this, window)
    this.pageModule = null
    this.state = null
    this.store = new Store()
    this.window = window

    this.loadPageOnPopStateEvents()
  }
  
  

  // TODO: refactor & test
  static getModule(module) {
    let name;

    if (module.type == "module") {
      name = module.className
    } else {
      name = module
    }

    return Utils.eval(name.replace(/\./g, ""))
  }  

  // TODO: refactor & test
  // DEFER: build event struct and pass to handleEvent
  handleClickEvent(onClickSpec, context, event) {
    event.preventDefault()
    this.handleEvent(onClickSpec, context)
  }

  handleEvent(eventHandlerSpec, context) {
    if (eventHandlerSpec.modifiers.includes("command")) {
      this.processCommand(eventHandlerSpec, context)

    } else {
      this.processAction(eventHandlerSpec, context)
    }
  }

  processCommand() {
    // this.pushCommand(eventHandlerSpec, context)
    this.client.pushCommand(context.pageModule, commandName, commandParams, this.handleCommandResponse)
  }

  processAction() {
    const actionResult = this.executeAction(eventHandlerSpec, context)

    if (actionResult.type == "tuple") {
      this.state = actionResult.data[0]

      let commandName = {type: "atom", value: actionResult.data[1].value}

      let commandParams = {type: "map", data: {}}
      if (actionResult.data[2]) {
        commandParams = actionResult.data[2]
      }

      this.client.pushCommand(targetModule, commandName, commandParams, this.handleCommandResponse)

    } else {
      if (isPageTarget) {
        this.state = actionResult
      } else {
        // TODO: handle non-page targets
      }
    }

    this.dom.render(context.pageModule)
  }
 
  // Covered by E2E tests.
  handleCommandResponse(response) {
    response = Utils.eval(response)
    const action = response.data[0]
    const params = response.data[1]

    if (action.value == "__redirect__") {
      this.handleRedirect(params)

    } else {
      const targetModule = this.getModule(response.data[2].className)
      this.executeAction2(targetModule, action, params, this.state)
    }
  }

  // TODO: refactor & test
  handleRedirect(params) {
    const html = params.data["~atom[html]"].value
    this.loadPage(html)

    const url = params.data["~atom[url]"].value
    this.updateURL(url)
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
    this.state = Utils.eval(serializedState, false)
    this.state.data["~atom[context]"].data['~atom[__state__]'] = {type: "string", value: serializedState}
    Utils.freeze(this.state)

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