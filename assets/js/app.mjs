"use strict";

import SubscriptionReceiptRegistry from "./subscription_receipt_registry.mjs";

export default class App {
  // Stable per JS context (across page navigation).
  // Populated from globalThis during Hologram boot.
  static instanceId = null;

  static subscriptionReceiptRegistry = SubscriptionReceiptRegistry;

  // Idempotent: returns early when `App.instanceId` is already set so a
  // snapshot-restored value survives the boot sequence even though
  // `#restorePageSnapshot` runs before `App.maybeLoadInstanceId()`.
  static maybeLoadInstanceId() {
    if (App.instanceId !== null) {
      return;
    }

    App.instanceId = globalThis.Hologram.instanceId;
  }
}
