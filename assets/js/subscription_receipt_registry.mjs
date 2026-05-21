"use strict";

import Type from "./type.mjs";

export default class SubscriptionReceiptRegistry {
  // Keyed by the encoded form of {channel, cid} (via Type.encodeMapKey).
  // Each value is the original Hologram-typed tuple
  // Type.tuple([channel, cid, token]) from the wire - kept as-is so the
  // handshake POST can ship values straight back without conversion.
  static entries = new Map();

  // Removes the dropped {channel, cid} keys (idempotent if absent), then adds
  // the new {channel, cid, token} entries (overwriting any existing entry for
  // the same key). Entries not mentioned in either list are left in place.
  // Both args are Hologram-typed lists of tuples - adds carries
  // {channel, cid, token} triples; drops carries {channel, cid} pairs.
  static merge(adds, drops) {
    for (const drop of drops.data) {
      $.entries.delete(Type.encodeMapKey(drop));
    }

    for (const triple of adds.data) {
      const [channel, cid] = triple.data;
      const encodedKey = Type.encodeMapKey(Type.tuple([channel, cid]));
      $.entries.set(encodedKey, triple);
    }
  }

  // Replaces `entries` with a fresh Map built from the given iterable of
  // [encodedKey, triple] pairs. Used by the page-snapshot restore path to
  // reinstate the registry after history navigation when bfcache did not
  // preserve the JS context. Mirrors `ComponentRegistry.populate/1`; the
  // iterable accepts whatever `Serializer.serialize` → `Deserializer.deserialize`
  // produces for the save-side `Array.from(entries.entries())` form.
  static populate(entries) {
    $.entries = new Map(entries);
  }

  static purge(keys) {
    $.merge(Type.list(), keys);
  }
}

const $ = SubscriptionReceiptRegistry;
