"use strict";

import Config from "./config.mjs";
import Connection from "./connection.mjs";

// Covered in feature tests
export default class Client {
  static connect() {
    return Connection.connect();
  }

  static fetchPage(toParam, onSuccess, onFail) {
    const opts = {
      onSuccess,
      onError: onFail,
      onTimeout: onFail,
      timeout: Config.fetchPageTimeoutMs,
    };

    return Connection.sendRequest("page", toParam, opts);
  }

  static fetchPageBundlePath(pageModule, onSuccess, onFail) {
    const opts = {
      onSuccess,
      onError: onFail,
      onTimeout: onFail,
      timeout: Config.clientFetchTimeoutMs,
    };

    return Connection.sendRequest("page_bundle_path", pageModule, opts);
  }

  static isConnected() {
    return Connection.isConnected();
  }

  static sendCommand(payload, onSuccess, onFail) {
    const opts = {
      onSuccess,
      onError: onFail,
      onTimeout: onFail,
    };

    return Connection.sendRequest("command", payload, opts);
  }
}
