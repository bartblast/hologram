"use strict";

import SubscriptionReceiptRegistry from "./subscription_receipt_registry.mjs";

export default class App {
  // Stable per JS context (across page navigation).
  // Populated from globalThis during Hologram boot.
  static instanceId = null;

  static subscriptionReceiptRegistry = SubscriptionReceiptRegistry;

  // Idempotent: returns early when `App.instanceId` is already set, so a second
  // call never replaces the id the tab already uses. The boot calls it before
  // any snapshot is restored, and a restore then puts the snapshot's id in
  // place itself (see `Hologram.#restorePageSnapshot`).
  static maybeLoadInstanceId() {
    if (App.instanceId !== null) {
      return;
    }

    App.instanceId = globalThis.Hologram.instanceId;
  }
}
