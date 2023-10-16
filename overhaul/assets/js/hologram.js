"use strict";

import Runtime from "./hologram/runtime";

export default class Hologram {
  static run() {
    Hologram.onReady(window.document, () => {
      if (!Runtime.isInitiated) {
        Runtime.init(window);
      }

      const args = window.hologramArgs;
      const storeSnapshot = window.hologramStoreSnapshot;
      const state = storeSnapshot ? storeSnapshot : args.state;

      Runtime.mountPage(args.class, args.digest, state);
    });
  }
}