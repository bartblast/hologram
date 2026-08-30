"use strict";

// Which identity this browser presents when it writes and when it connects.
//
// A replica is one browser's copy of the data, and the server mints its identity: an id and a
// signed statement of whom that id belongs to, emitted into every initial page render. So every
// page load OFFERS a fresh pair, and a browser that already remembers one ignores the offer -
// re-minting per load would abandon the numbering its batches are identified by, and the server
// would answer a new load's first batch from the record of the last load's first batch.
//
// The offer is kept rather than dropped, because it is the recovery. A remembered statement stops
// verifying when the session it was bound to is gone, or after the server's signing key is
// rotated, and the server refuses such a batch outright - at which point the pair this page was
// handed is exactly the fresh, valid one to switch to, and it is already here.
export default class Replica {
  // The pair the current page offered, held whether or not it is the one in use.
  static fresh = null;

  static id = null;

  static token = null;

  static adopt(replica) {
    Replica.id = replica.id;
    Replica.token = replica.token;
  }

  // The pair in use, as one value - what gets written down, and what a batch presents.
  static current() {
    return {id: Replica.id, token: Replica.token};
  }

  // What the page hands over. Taken into use only when nothing is in use yet, which is a browser
  // that remembers no identity: a first ever visit, or one whose remembered rows and identity were
  // dropped because somebody else is signed in now.
  //
  // A build carrying no data model emits no pair, and normalizing the two halves to nothing keeps
  // "an absent identity is null" true here rather than leaving undefined to travel.
  static offer(replica) {
    Replica.fresh = {id: replica.id ?? null, token: replica.token ?? null};

    if (Replica.id === null) {
      Replica.adopt(Replica.fresh);
    }
  }

  // Switches to the pair the page offered, answering whether there was anywhere to switch TO. No
  // when the offer is already what is in use, since a pair the server just refused cannot be
  // recovered by presenting it again, and no when the page offered nothing at all.
  static refresh() {
    if (!Replica.fresh?.id || Replica.fresh.id === Replica.id) {
      return false;
    }

    Replica.adopt(Replica.fresh);

    return true;
  }

  static reset() {
    Replica.fresh = null;
    Replica.id = null;
    Replica.token = null;
  }
}
