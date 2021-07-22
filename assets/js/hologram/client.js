import { Socket } from "phoenix";

export default class Client {
  constructor(runtime) {
    this.channel = null
    this.isConnected = false
    this.runtime = runtime
    this.socket = null
  }

  static buildMessagePayload(command, params, context) {
    return {
      command: command,
      context: {
        page_module: context.pageModule.name,
        scope_module: context.scopeModule.name
      },
      params: params
    }
  }

  async connect() {
    const socket = new Socket("/hologram");
    socket.connect();

    const channel = socket.channel("hologram");

    channel
      .join()
      .receive("ok", (_) => {
        this.isConnected = true
      });

    this.socket = socket
    this.channel = channel
  }

  async pushCommand(command, params, context) {
    const payload = Client.buildMessagePayload(command, params, context)

    this.channel
      .push("command", payload)
      .receive("ok", (response) => {
        this.runtime.handleCommandResponse(response)
      })
      .receive("error", (_response) => {
        console.log("Command error")
        console.debug(arguments)
      })
      .receive("timeout", () => {
        console.log("Command timeout")
        console.debug(arguments)
      });
  }
}