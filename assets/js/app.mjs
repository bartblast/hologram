"use strict";

export default class App {
  // Stable identifier for this app instance (tab / window / desktop or mobile
  // app process). Generated fresh on each JS context load, so a hard refresh
  // or a new tab gets a new id; same id for the lifetime of the window object,
  // which means it survives SSE reconnects and Hologram in-page navigation.
  static instanceId = crypto.randomUUID();
}
