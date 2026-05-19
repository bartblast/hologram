"use strict";

import SubscriptionReceiptRegistry from "./subscription_receipt_registry.mjs";

export default class App {
  // Stable per JS context (across page navigation).
  // Populated from globalThis during Hologram boot.
  static instanceId = null;

  static subscriptionReceiptRegistry = SubscriptionReceiptRegistry;

  static loadInstanceId() {
    App.instanceId = globalThis.Hologram.instanceId;
  }
}
