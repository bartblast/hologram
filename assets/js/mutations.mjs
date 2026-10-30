"use strict";

import App from "./app.mjs";
import Config from "./config.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import Replica from "./replica.mjs";

// The client side of the mutation endpoint: the envelope a batch of writes ships as, and the
// request that carries it to the server and reads back its answer.
export default class Mutations {
  // The envelope a batch ships as. Plain JSON, the spelling a sync frame uses in reverse - the
  // client holds rows as the wire spells them, so what goes back is what came in.
  //
  // The identity is whichever pair this browser presents - the one it remembered from an earlier
  // page load, or the current page's when it remembers none. Both halves are the server's: it
  // mints them at an initial page render, and the token is its signed statement of whom the id
  // belongs to, which is what stops a stranger who learns an id from spending its sequence
  // numbers.
  static buildPayload(batch) {
    return {
      instance_id: App.instanceId,
      model_hash: globalThis.Hologram.sync.modelHash,
      replica_id: Replica.id,
      replica_token: Replica.token,
      seq: batch.seq,
      writes: batch.writes,
    };
  }

  // Answers what the server said about a batch, in one of three shapes:
  //
  //   {status: "confirmed", dropped, kept} - applied; dropped names the values that LOST and
  //                                          kept the ones standing in their place
  //   {status: "rejected", write, reason}  - refused; reason is a serialized term
  //   {status: "failed", httpStatus}       - no verdict at all, so the batch is still pending
  //
  // A confirmation is handed back exactly as it arrived. Both of its maps are keyed by the
  // write's position as a string, and their values are wire spellings - the same shape a frame
  // carries - so nothing here has to know what a column holds in order to pass it on.
  //
  // The third is not a rejection and must never be treated as one: a 403 says the identity was
  // refused before the writes were read, and a network failure says nothing was read at all. What
  // the sender does about it is its own decision.
  //
  // A 400 is different again - it means this client built a malformed envelope, which is a bug in
  // the framework rather than an answer about the writes, so it is raised loudly.
  //
  // The deadline is not politeness either: a request that connects and then goes quiet never
  // settles, and the sender loop holds its guard until it does - so one dead connection would stop
  // the queue for the life of the page rather than for one send. Aborting makes it an ordinary
  // no-verdict answer, which the loop already keeps pending and tries again.
  static async send(batch) {
    const controller = new AbortController();

    const opts = {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Csrf-Token": globalThis.Hologram.csrfToken,
      },
      body: JSON.stringify($.buildPayload(batch)),
      signal: controller.signal,
    };

    const deadline = setTimeout(
      () => controller.abort(),
      Config.mutationTimeoutMs,
    );

    // Cleared only once the answer is READ, not once the response arrives - a body that never
    // streams is the same silence as a request that never answers.
    try {
      const response = await fetch("/hologram/mutation", opts);

      if (response.status === 400) {
        throw new HologramRuntimeError(
          `mutation failed: ${await response.text()}`,
        );
      }

      if (!response.ok) {
        return {httpStatus: response.status, status: "failed"};
      }

      // Answered exactly as the server spelled it, the serialized reason of a refusal included.
      // Reading that term is the queue's, at the one place a reason is ever looked at - which is
      // what leaves this answer a plain JSON value, and so something a browser can hand from one
      // tab to another the way it hands a frame.
      return await response.json();
    } finally {
      clearTimeout(deadline);
    }
  }
}

const $ = Mutations;
