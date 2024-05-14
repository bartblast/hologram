"use strict";

import {Socket} from "phoenix";

// Tested implicitely in feature tests.
export default class Client {
  static async connect() {
    const socket = new Socket("/hologram");
    socket.connect();

    socket
      .channel("hologram")
      .join()
      .receive("ok", (_resp) => {
        console.debug("Joined Hologram channel");
      })
      .receive("error", (_resp) => {
        console.error("Unable to join Hologram channel");
      });
  }
}
