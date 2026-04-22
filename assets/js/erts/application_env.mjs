"use strict";

import Type from "../type.mjs";

export default class ApplicationEnv {
  // Nested Map: app_string -> key_string -> value
  // Public for easier testing
  static data = new Map();

  static clear() {
    $.data = new Map();
  }

  static get(app, key, defaultValue) {
    const encodedApp = Type.encodeMapKey(app);

    if (!$.data.has(encodedApp)) {
      return defaultValue;
    }

    const appData = $.data.get(encodedApp);
    const encodedKey = Type.encodeMapKey(key);

    return appData.has(encodedKey) ? appData.get(encodedKey) : defaultValue;
  }

  static put(app, key, value) {
    const encodedApp = Type.encodeMapKey(app);

    if (!$.data.has(encodedApp)) {
      $.data.set(encodedApp, new Map());
    }

    const encodedKey = Type.encodeMapKey(key);
    $.data.get(encodedApp).set(encodedKey, value);
  }
}

const $ = ApplicationEnv;
