"use strict";

export default class App {
  // Stable per JS context (across page navigation).
  // Populated from globalThis during Hologram boot.
  static instanceId = null;

  static loadInstanceId() {
    App.instanceId = globalThis.Hologram.instanceId;
  }
}
