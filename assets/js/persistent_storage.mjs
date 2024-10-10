"use strict";

import HologramRuntimeError from "./errors/runtime_error.mjs";

export default class PersistentStorage {
  // Made public to make tests easier
  static db = null;

  static PAGE_SNAPSHOTS_OBJ_STORE_NAME = "pageSnapshots";

  static init(env) {
    return new Promise((resolve) => {
      const request = indexedDB.open(`hologram_${env}`, 1);

      request.onerror = (_event) => {
        throw new HologramRuntimeError(
          "failed to initiate client persistent storage",
        );
      };

      request.onsuccess = (event) => {
        $.db = event.target.result;
        resolve(event.target.result);
      };

      request.onupgradeneeded = (event) => {
        $.db = event.target.result;

        const objectStore = $.db.createObjectStore(
          $.PAGE_SNAPSHOTS_OBJ_STORE_NAME,
          {
            autoIncrement: true,
          },
        );

        objectStore.createIndex("createdAt", "createdAt", {unique: false});
      };
    });
  }

  static getPageSnapshot(id) {
    return new Promise((resolve) => {
      const request = $.db
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

  static putPageSnapshot(data) {
    return new Promise((resolve) => {
      const obj = {data, createdAt: new Date()};

      const request = $.db
        .transaction($.PAGE_SNAPSHOTS_OBJ_STORE_NAME, "readwrite")
        .objectStore($.PAGE_SNAPSHOTS_OBJ_STORE_NAME)
        .put(obj);

      request.onerror = (_event) => {
        throw new HologramRuntimeError(
          "failed to save page snapshot to client persistent storage",
        );
      };

      request.onsuccess = (event) => resolve(event.target.result);
    });
  }
}

const $ = PersistentStorage;
