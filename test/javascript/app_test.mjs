"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import App from "../../assets/js/app.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("App", () => {
  describe("loadInstanceId()", () => {
    let originalGlobalHologram;

    beforeEach(() => {
      originalGlobalHologram = globalThis.Hologram;
    });

    afterEach(() => {
      if (originalGlobalHologram === undefined) {
        delete globalThis.Hologram;
      } else {
        globalThis.Hologram = originalGlobalHologram;
      }

      App.instanceId = null;
    });

    it("reads instanceId from globalThis.Hologram into App.instanceId", () => {
      globalThis.Hologram = {instanceId: "abc-123"};

      App.loadInstanceId();

      assert.equal(App.instanceId, "abc-123");
    });

    it("overwrites a previously loaded instanceId on subsequent calls", () => {
      globalThis.Hologram = {instanceId: "first"};
      App.loadInstanceId();

      globalThis.Hologram = {instanceId: "second"};
      App.loadInstanceId();

      assert.equal(App.instanceId, "second");
    });
  });

  describe("mergeReceipts()", () => {
    const receipt = (channel, cid, token) =>
      Type.tuple([channel, Type.bitstring(cid), Type.bitstring(token)]);

    const key = (channel, cid) => Type.tuple([channel, Type.bitstring(cid)]);
    const encodedKey = (channel, cid) => Type.encodeMapKey(key(channel, cid));

    beforeEach(() => {
      App.subscriptionReceipts.clear();
    });

    afterEach(() => {
      App.subscriptionReceipts.clear();
    });

    it("adds entries from adds list", () => {
      const adds = Type.list([receipt(Type.atom("room_a"), "page", "token-a")]);

      App.mergeReceipts(adds, Type.list());

      const stored = App.subscriptionReceipts.get(
        encodedKey(Type.atom("room_a"), "page"),
      );

      assert.equal(stored.data[2].text, "token-a");
    });

    it("removes entries listed in drops", () => {
      App.mergeReceipts(
        Type.list([receipt(Type.atom("room_a"), "page", "token-a")]),
        Type.list(),
      );

      App.mergeReceipts(
        Type.list(),
        Type.list([key(Type.atom("room_a"), "page")]),
      );

      assert.isFalse(
        App.subscriptionReceipts.has(encodedKey(Type.atom("room_a"), "page")),
      );
    });

    it("leaves entries not mentioned in adds or drops in place", () => {
      App.mergeReceipts(
        Type.list([
          receipt(Type.atom("room_a"), "page", "token-a"),
          receipt(Type.atom("room_b"), "comp_1", "token-b"),
        ]),
        Type.list(),
      );

      App.mergeReceipts(
        Type.list([receipt(Type.atom("room_c"), "page", "token-c")]),
        Type.list([key(Type.atom("room_a"), "page")]),
      );

      const surviving = App.subscriptionReceipts.get(
        encodedKey(Type.atom("room_b"), "comp_1"),
      );

      assert.equal(surviving.data[2].text, "token-b");
    });

    it("overwrites an existing entry when the same key is added again", () => {
      App.mergeReceipts(
        Type.list([receipt(Type.atom("room_a"), "page", "old-token")]),
        Type.list(),
      );

      App.mergeReceipts(
        Type.list([receipt(Type.atom("room_a"), "page", "new-token")]),
        Type.list(),
      );

      const stored = App.subscriptionReceipts.get(
        encodedKey(Type.atom("room_a"), "page"),
      );

      assert.equal(stored.data[2].text, "new-token");
    });

    it("is a no-op when dropping a key that is not present", () => {
      App.mergeReceipts(
        Type.list(),
        Type.list([key(Type.atom("room_a"), "page")]),
      );

      assert.equal(App.subscriptionReceipts.size, 0);
    });
  });

  describe("purgeReceipts()", () => {
    const receipt = (channel, cid, token) =>
      Type.tuple([channel, Type.bitstring(cid), Type.bitstring(token)]);

    const key = (channel, cid) => Type.tuple([channel, Type.bitstring(cid)]);
    const encodedKey = (channel, cid) => Type.encodeMapKey(key(channel, cid));

    beforeEach(() => {
      App.subscriptionReceipts.clear();
    });

    afterEach(() => {
      App.subscriptionReceipts.clear();
    });

    it("removes the listed keys and leaves other entries in place", () => {
      App.mergeReceipts(
        Type.list([
          receipt(Type.atom("room_a"), "page", "token-a"),
          receipt(Type.atom("room_b"), "comp_1", "token-b"),
        ]),
        Type.list(),
      );

      App.purgeReceipts(Type.list([key(Type.atom("room_a"), "page")]));

      assert.isFalse(
        App.subscriptionReceipts.has(encodedKey(Type.atom("room_a"), "page")),
      );

      const surviving = App.subscriptionReceipts.get(
        encodedKey(Type.atom("room_b"), "comp_1"),
      );

      assert.equal(surviving.data[2].text, "token-b");
    });
  });
});
