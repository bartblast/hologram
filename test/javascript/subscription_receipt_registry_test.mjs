"use strict";

import {
  assert,
  defineRuntimeGlobals,
  encodedSubscriptionReceiptKey,
} from "./support/helpers.mjs";

import SubscriptionReceiptRegistry from "../../assets/js/subscription_receipt_registry.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

describe("SubscriptionReceiptRegistry", () => {
  const receipt = (channel, cid, token) =>
    Type.tuple([channel, Type.bitstring(cid), Type.bitstring(token)]);

  const key = (channel, cid) => Type.tuple([channel, Type.bitstring(cid)]);

  beforeEach(() => {
    SubscriptionReceiptRegistry.entries.clear();
  });

  afterEach(() => {
    SubscriptionReceiptRegistry.entries.clear();
  });

  describe("merge()", () => {
    it("adds entries from adds list", () => {
      const adds = Type.list([receipt(Type.atom("room_a"), "page", "token-a")]);

      SubscriptionReceiptRegistry.merge(adds, Type.list());

      const stored = SubscriptionReceiptRegistry.entries.get(
        encodedSubscriptionReceiptKey(Type.atom("room_a"), "page"),
      );

      assert.equal(stored.data[2].text, "token-a");
    });

    it("removes entries listed in drops", () => {
      SubscriptionReceiptRegistry.merge(
        Type.list([receipt(Type.atom("room_a"), "page", "token-a")]),
        Type.list(),
      );

      SubscriptionReceiptRegistry.merge(
        Type.list(),
        Type.list([key(Type.atom("room_a"), "page")]),
      );

      assert.isFalse(
        SubscriptionReceiptRegistry.entries.has(
          encodedSubscriptionReceiptKey(Type.atom("room_a"), "page"),
        ),
      );
    });

    it("leaves entries not mentioned in adds or drops in place", () => {
      SubscriptionReceiptRegistry.merge(
        Type.list([
          receipt(Type.atom("room_a"), "page", "token-a"),
          receipt(Type.atom("room_b"), "comp_1", "token-b"),
        ]),
        Type.list(),
      );

      SubscriptionReceiptRegistry.merge(
        Type.list([receipt(Type.atom("room_c"), "page", "token-c")]),
        Type.list([key(Type.atom("room_a"), "page")]),
      );

      const surviving = SubscriptionReceiptRegistry.entries.get(
        encodedSubscriptionReceiptKey(Type.atom("room_b"), "comp_1"),
      );

      assert.equal(surviving.data[2].text, "token-b");
    });

    it("overwrites an existing entry when the same key is added again", () => {
      SubscriptionReceiptRegistry.merge(
        Type.list([receipt(Type.atom("room_a"), "page", "old-token")]),
        Type.list(),
      );

      SubscriptionReceiptRegistry.merge(
        Type.list([receipt(Type.atom("room_a"), "page", "new-token")]),
        Type.list(),
      );

      const stored = SubscriptionReceiptRegistry.entries.get(
        encodedSubscriptionReceiptKey(Type.atom("room_a"), "page"),
      );

      assert.equal(stored.data[2].text, "new-token");
    });

    it("is a no-op when dropping a key that is not present", () => {
      SubscriptionReceiptRegistry.merge(
        Type.list(),
        Type.list([key(Type.atom("room_a"), "page")]),
      );

      assert.equal(SubscriptionReceiptRegistry.entries.size, 0);
    });
  });

  describe("populate()", () => {
    it("replaces existing entries with the passed iterable", () => {
      const oldReceipt = receipt(Type.atom("room_a"), "page", "token-a");
      const newReceipt = receipt(Type.atom("room_b"), "comp_1", "token-b");
      const newKey = Type.encodeMapKey(key(Type.atom("room_b"), "comp_1"));

      SubscriptionReceiptRegistry.populate([["old-key", oldReceipt]]);
      SubscriptionReceiptRegistry.populate([[newKey, newReceipt]]);

      assert.equal(SubscriptionReceiptRegistry.entries.size, 1);
      assert.equal(SubscriptionReceiptRegistry.entries.get(newKey), newReceipt);
    });

    it("keys each entry by its own channel and cid, whatever key it came with", () => {
      const triple = receipt(Type.atom("room_a"), "page", "token-a");
      const currentKey = Type.encodeMapKey(key(Type.atom("room_a"), "page"));

      SubscriptionReceiptRegistry.populate([["stale-key", triple]]);

      assert.equal(SubscriptionReceiptRegistry.entries.get(currentKey), triple);
      assert.isFalse(SubscriptionReceiptRegistry.entries.has("stale-key"));
    });
  });

  describe("purge()", () => {
    it("removes the listed keys and leaves other entries in place", () => {
      SubscriptionReceiptRegistry.merge(
        Type.list([
          receipt(Type.atom("room_a"), "page", "token-a"),
          receipt(Type.atom("room_b"), "comp_1", "token-b"),
        ]),
        Type.list(),
      );

      SubscriptionReceiptRegistry.purge(
        Type.list([key(Type.atom("room_a"), "page")]),
      );

      assert.isFalse(
        SubscriptionReceiptRegistry.entries.has(
          encodedSubscriptionReceiptKey(Type.atom("room_a"), "page"),
        ),
      );

      const surviving = SubscriptionReceiptRegistry.entries.get(
        encodedSubscriptionReceiptKey(Type.atom("room_b"), "comp_1"),
      );

      assert.equal(surviving.data[2].text, "token-b");
    });
  });
});
