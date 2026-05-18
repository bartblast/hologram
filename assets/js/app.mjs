"use strict";

import Type from "./type.mjs";

export default class App {
  // Stable per JS context (across page navigation).
  // Populated from globalThis during Hologram boot.
  static instanceId = null;

  // Keyed by the encoded form of {channel, cid} (via Type.encodeMapKey).
  // Each value is the original Hologram-typed tuple
  // Type.tuple([channel, cid, token]) from the wire - kept as-is so the
  // handshake POST can ship values straight back without conversion.
  // Mutated by mergeReceipts/purgeReceipts.
  static subscriptionReceipts = new Map();

  static loadInstanceId() {
    $.instanceId = globalThis.Hologram.instanceId;
  }

  // Updates subscriptionReceipts: removes the dropped {channel, cid} keys
  // (idempotent if absent), then adds the new {channel, cid, token} entries
  // (overwriting any existing entry for the same key). Entries not mentioned
  // in either list are left in place. Both args are Hologram-typed lists of
  // tuples - adds carries {channel, cid, token} triples; drops carries
  // {channel, cid} pairs.
  static mergeReceipts(adds, drops) {
    for (const drop of drops.data) {
      $.subscriptionReceipts.delete(Type.encodeMapKey(drop));
    }

    for (const triple of adds.data) {
      const [channel, cid] = triple.data;
      const encodedKey = Type.encodeMapKey(Type.tuple([channel, cid]));
      $.subscriptionReceipts.set(encodedKey, triple);
    }
  }

  // Convenience for callers that only need to remove entries.
  static purgeReceipts(keys) {
    $.mergeReceipts(Type.list(), keys);
  }
}

const $ = App;
