"use strict";

import SubscriptionReceiptRegistry from "./subscription_receipt_registry.mjs";

export default class App {
  // The nonce the document's Content Security Policy names, which the elements the runtime creates
  // carry. Per document, so it never enters a page snapshot. Null when the document has none.
  static cspNonce = null;

  // Stable per JS context (across page navigation).
  // Populated from globalThis during Hologram boot.
  static instanceId = null;

  static subscriptionReceiptRegistry = SubscriptionReceiptRegistry;

  // The nonce is per document, so it is read from the document's own shell script, and is null
  // when that script set none.
  static loadCspNonce() {
    App.cspNonce = globalThis.Hologram.cspNonce ?? null;
  }

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
