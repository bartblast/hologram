"use strict";

import HologramRuntimeError from "./errors/runtime_error.mjs";

export default class PersistentStorage {
  // Made public to make tests easier
  static env = null;

  static PAGE_SNAPSHOTS_OBJ_STORE_NAME = "pageSnapshots";

  static async database() {
    return new Promise((resolve) => {
      const request = indexedDB.open(`hologram_${$.env}`, 1);

      request.onerror = (_event) => {
        throw new HologramRuntimeError(
          "failed to initiate client persistent storage",
        );
      };

      request.onsuccess = (event) => {
        resolve(event.target.result);
      };

      request.onupgradeneeded = (event) => {
        event.target.result
          .createObjectStore($.PAGE_SNAPSHOTS_OBJ_STORE_NAME, {
            keyPath: "id",
          })
          .createIndex("createdAt", "createdAt", {unique: false});
      };
    });
  }

  static async getPageSnapshot(id) {
    const db = await $.database();

    return new Promise((resolve) => {
      const request = db
        .transaction($.PAGE_SNAPSHOTS_OBJ_STORE_NAME, "readonly")
        .objectStore($.PAGE_SNAPSHOTS_OBJ_STORE_NAME)
        .get(id);

      request.onerror = (_event) => {
        throw new HologramRuntimeError(
          "failed to load page snapshot from client persistent storage",
        );
      };

      request.onsuccess = (event) => resolve(event.target.result);
    });
  }

  static async init(env) {
    $.env = env;
    return $.database();
  }

  static async putPageSnapshot(id, data) {
    const db = await $.database();

    return new Promise((resolve) => {
      const obj = {id, data, createdAt: new Date()};

      const request = db
        .transaction($.PAGE_SNAPSHOTS_OBJ_STORE_NAME, "readwrite")
        .objectStore($.PAGE_SNAPSHOTS_OBJ_STORE_NAME)
        .put(obj);

      request.onerror = (_event) => {
        throw new HologramRuntimeError(
          "failed to save page snapshot to client persistent storage",
        );
      };

      request.onsuccess = (_event) => resolve(id);
    });
  }
}

const $ = PersistentStorage;
