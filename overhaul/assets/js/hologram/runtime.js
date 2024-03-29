"use strict";

import Action from "./action";
import Client from "./client"
import Command from "./command"
import Operation from "./operation"
import ScriptsReloader from "./scripts_reloader"
import Store from "./store";
import Target from "./target";
import Type from "./type";
import Utils from "./utils"
import VDOM from "./vdom"

const morphdom = require("morphdom");

export default class Runtime {
  static componentClassRegistry = {}
  static document = null
  static staticDigestStore = null
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

  static getComponentClass(componentId) {
    const klass = Runtime.componentClassRegistry[componentId]
    return klass ? klass : null
  }

  static getLayoutClass() {
    return Runtime.getComponentClass(Target.TYPE.layout)
  }

  static getLayoutTemplate() {
    return Runtime.getLayoutClass().template()
  }

  static getPageClass() {
    return Runtime.getComponentClass(Target.TYPE.page)
  }

  static getPageTemplate() {
    return Runtime.getPageClass().template()
  }

  // Covered implicitely in E2E tests.
  static handleEvent(event, eventImplementation, sourceId, bindings, operationSpec, tag) {
    if (eventImplementation.shouldHandleEvent(event)) {
      event.preventDefault()

      const eventData = eventImplementation.buildEventData(event, tag)
      const operation = Operation.build(operationSpec, sourceId, bindings, eventData)

      Runtime.executeOperation(operation)
    }
  }

  // Covered implicitely in E2E tests.
  static init(window) {
    Client.connect(window)

    Runtime.document = window.document
    Runtime.window = window

    Runtime.staticDigestStore = window.__hologramStaticDigestStore__

    Runtime.loadPageOnPopStateEvents()

    Runtime.isInitiated = true
  }

  // Covered implicitely in E2E tests.
  static loadPage(html, storeSnapshot) {
    window.hologramRuntimeScriptLoaded = false
    window.hologramPageScriptLoaded = false
    window.hologramPageMounted = false
    Runtime.window.hologramStoreSnapshot = storeSnapshot

    // DEFER: copy html node attributes (because only the inner HTML is updated)
    var el = Runtime.document.createElement("html")
    el.innerHTML = html

    requestAnimationFrame(() => {
      morphdom(Runtime.document.head, el.querySelector("head"))
      Runtime.document.body = el.querySelector("body")

      // DEFER: test
      Runtime.window.scrollTo(0, 0)

      VDOM.reset()
      ScriptsReloader.reload(Runtime.document)
    })
  }

  // Covered implicitely in E2E tests.
  static loadPageOnPopStateEvents() {
    Runtime.window.addEventListener("popstate", event => {
      Runtime.loadPage(event.state.html, event.state.storeSnapshot)
    })
  }

  // Covered implicitely in E2E tests.
  static mountPage(pageClassName, digest, state) {
    const pageClass = Runtime.getClassByClassName(pageClassName)
    Runtime.registerPageClass(pageClass)

    const layoutClass = Runtime.determineLayoutClass(pageClass)
    Runtime.registerLayoutClass(layoutClass)

    Store.hydrate(pageClassName, digest, state)
    VDOM.render()

    const html = VDOM.getDocumentHTML(Runtime.document)

    // DEFER: consider - there are limitations for state object size, e.g. 2 MB for Firefox
    const historyState = {
      html: html,
      storeSnapshot: state
    }

    Runtime.window.history.replaceState(historyState, null)
  }

  // Covered implicitely in E2E tests.
  static redirect(params) {
    const html = params.data[Type.atomKey("html")].value
    Runtime.loadPage(html, null)

    const url = params.data[Type.atomKey("url")].value
    Runtime.updateURL(url)
  }

  static registerComponentClass(componentId, klass) {
    Runtime.componentClassRegistry[componentId] = klass
  }

  static registerLayoutClass(klass) {
    Runtime.registerComponentClass(Target.TYPE.layout, klass)
  }

  static registerPageClass(klass) {
    Runtime.registerComponentClass(Target.TYPE.page, klass)
  }

  static resolveComponentClass(node, componentId) {
    if (componentId) {
      let klass = Runtime.getComponentClass(componentId)

      if (!klass) {
        klass = Runtime.getClassByClassName(node.className)
        Runtime.registerComponentClass(componentId, klass)
      }

      return klass

    } else {
      return Runtime.getClassByClassName(node.className)
    }
  }

  // Covered implicitely in E2E tests.
  static updateURL(url) {
    Runtime.window.history.pushState(null, null, url)
  }
}