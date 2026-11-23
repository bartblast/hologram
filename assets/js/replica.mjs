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

  // Whether this tab is waiting for the server to mint it a pair of its own (see requestMint).
  static awaitingMint = false;

  // Whether the pair in use is one the server minted for this tab alone.
  static minted = false;

  // Whether the server refused to mint one, because the pair this tab showed it no longer holds
  // for whoever is signed in (see refuseMint).
  static mintRefused = false;

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

  // Asks for a pair no other tab can hold, for a tab that counts its batches in memory. The pair in
  // its page can't be that: a browser can serve one cached page to two tabs, or again on Back, and
  // each would count from 1 under it, so the server would answer one write from the record of
  // another. The next stream handshake brings the pair, and nothing is sent until it has.
  static requestMint() {
    Replica.awaitingMint = true;
  }

  // The pair the server minted, put in use if this tab is still waiting for one, answering whether
  // it was. The page's pair is let go of for good: refresh() going back to it would undo the point
  // of asking.
  static takeMinted(replica) {
    if (!Replica.withoutIdentity() || !replica?.id) {
      return false;
    }

    Replica.awaitingMint = false;
    Replica.fresh = null;
    Replica.minted = true;
    Replica.mintRefused = false;

    Replica.adopt(replica);

    return true;
  }

  // The server won't mint for the owner of the pair this tab showed. A stored pair can simply be
  // stale, from a session that has ended, so the page's own gets a turn. With that refused too,
  // somebody else holds the session: nothing goes out, since the writes this tab holds are its
  // owner's. It stops asking, and later handshakes still show the pair, so it recovers if its owner
  // signs back in.
  //
  // Only a refusal of the pair in use counts. Two handshakes can overlap and both show the stored
  // pair, and the second refusal would otherwise end the asking before the page's pair was tried.
  static refuseMint(presentedId = Replica.id) {
    if (
      !Replica.awaitingMint ||
      presentedId !== Replica.id ||
      Replica.refresh()
    ) {
      return;
    }

    Replica.awaitingMint = false;
    Replica.mintRefused = true;
  }

  // Whether this tab has no pair it may send under, for now or for good.
  static withoutIdentity() {
    return Replica.awaitingMint || Replica.mintRefused;
  }

  static reset() {
    Replica.awaitingMint = false;
    Replica.fresh = null;
    Replica.id = null;
    Replica.minted = false;
    Replica.mintRefused = false;
    Replica.token = null;
  }
}
