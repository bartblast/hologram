"use strict";

export default class App {
  // Stable per JS context (across page navigation).
  // Populated from globalThis during Hologram boot.
  static instanceId = null;

  static loadInstanceId() {
    $.instanceId = globalThis.Hologram.instanceId;
  }
}

const $ = App;
