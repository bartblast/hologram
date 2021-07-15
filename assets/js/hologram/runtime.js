import Client from "./client"
import DOM from "./dom"

export default class Runtime {
  constructor(pageModule, state) {
    this.client = new Client()
    this.dom = new DOM()
    this.pageModule = pageModule
    this.state = state
  }

  restart() {
    this.dom.render(this, this.pageModule)
  }
}