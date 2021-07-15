import Client from "./client"
import DOM from "./dom"

export default class Runtime {
  constructor() {
    this.client = new Client()
    this.dom = new DOM()
    this.pageModule = null
    this.state = null
  }

  restart(pageModule, state) {
    this.pageModule = pageModule
    this.state = state

    this.dom.render(this, this.pageModule)
  }
}