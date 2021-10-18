
  // TODO: refactor & test
  constructor(runtime, window) {
    this.document = window.document
    this.oldVNode = null
    this.runtime = runtime
    this.window = window
  }

  // TODO: refactor & test
  render(pageModule) {
    if (!this.oldVNode) {
      this.oldVNode = toVNode(this.document.documentElement)
    }

    const pageTemplate = pageModule.template()
    const layoutClassName = pageModule.layout().className
    const layoutTemplate = Runtime.getClassByClassName(layoutClassName).template()

    const context = {scopeModule: pageModule, pageModule: pageModule, slots: {default: pageTemplate}}

    let newVNode = this.buildVNode(layoutTemplate, this.runtime.state, this.runtime.state, context)[0]
    patch(this.oldVNode, newVNode)
    this.oldVNode = newVNode
  }

  // TODO: refactor & test
  reset() {
    this.oldVNode = null
  }