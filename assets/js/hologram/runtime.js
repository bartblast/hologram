"use strict";

import Action from "./action";
import Client from "./client"
import Command from "./command"
import Operation from "./operation"
import ScriptsReloader from "./scripts_reloader"
import Store from "./store";
import Type from "./type";
import Utils from "./utils"
import VDOM from "./vdom"

export default class Runtime {
  static componentClassRegistry = {}
  static document = null
  static isInitiated = false
  static window = null

  static determineLayoutClass(pageClass) {
    const layoutClassName = pageClass.layout().className
    return Runtime.getClassByClassName(layoutClassName)
  }

  // Covered implicitely in E2E tests.
  static executeOperation(operation) {
    if (operation.method === Operation.METHOD.action) {
      Action.execute(operation)
    } else {
      Command.execute(operation)
    }
  }

  static getClassByClassName(className) {
    return Utils.eval(className)
  }  

  static getComponentClass(componentId) {
    return Runtime.componentClassRegistry[componentId]
  }

  static getLayoutClass() {
    return Runtime.getComponentClass(Operation.TARGET.layout)
  }

  static getLayoutTemplate() {
    return Runtime.getLayoutClass().template()
  }

  static getPageClass() {
    return Runtime.getComponentClass(Operation.TARGET.page)
  }

  static getPageTemplate() {
    return Runtime.getPageClass().template()
  }

  // Covered implicitely in E2E tests.
  static handleEvent(event, eventImplementation, source, bindings, operationSpec) {
    event.preventDefault()

    const eventData = eventImplementation.buildEventData(event)
    const operation = Operation.build(operationSpec, source, bindings, eventData)

    Runtime.executeOperation(operation)
  }

  // Covered implicitely in E2E tests.
  static init(window) {
    Client.connect()

    Runtime.document = window.document
    Runtime.window = window

    Runtime.loadPageOnPopStateEvents()

    Runtime.isInitiated = true
  }

  // Covered implicitely in E2E tests.
  loadPage(html) {
    // DEFER: copy html node attributes (because only the inner HTML is updated)
    Runtime.document.documentElement.innerHTML = html

    VDOM.reset()
    ScriptsReloader.reload(Runtime.document)
  }

  // Covered implicitely in E2E tests.
  static loadPageOnPopStateEvents() {
    Runtime.window.addEventListener("popstate", event => {
      Runtime.loadPage(event.state)
    })
  }

  // Covered implicitely in E2E tests.
  static mountPage(pageClass, serializedState) {
    Runtime.registerPageClass(pageClass)

    const layoutClass = Runtime.determineLayoutClass(pageClass)
    Runtime.registerLayoutClass(layoutClass)

    Store.hydrate(serializedState)
    VDOM.render()

    const html = VDOM.getDocumentHTML(Runtime.document)

    // DEFER: consider - there are limitations for state object size, e.g. 2 MB for Firefox
    Runtime.window.history.replaceState(html, null)
  }

  // Covered implicitely in E2E tests.
  static redirect(params) {
    const html = params.data[Type.atomKey("html")].value
    Runtime.loadPage(html)

    const url = params.data[Type.atomKey("url")].value
    Runtime.updateURL(url)
  }

  static registerComponentClass(componentId, klass) {
    Runtime.componentClassRegistry[componentId] = klass
  }

  static registerLayoutClass(klass) {
    Runtime.registerComponentClass(Operation.TARGET.layout, klass)
  }

  static registerPageClass(klass) {
    Runtime.registerComponentClass(Operation.TARGET.page, klass)
  }

  // Covered implicitely in E2E tests.
  static updateURL(url) {
    Runtime.window.history.pushState(null, null, url)
  }
}