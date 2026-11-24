"use strict";

import {assert} from "./support/helpers.mjs";

import Replica from "../../assets/js/replica.mjs";

describe("Replica", () => {
  const fresh = {id: "replica-fresh", token: "token-fresh"};
  const stored = {id: "replica-stored", token: "token-stored"};

  // Module state, so it is dropped on both sides: a pair left behind here would be the identity
  // whatever suite runs next presents.
  beforeEach(() => {
    Replica.reset();
  });

  afterEach(() => {
    Replica.reset();
  });

  describe("adopt()", () => {
    it("puts the given pair in use", () => {
      Replica.adopt(stored);

      assert.equal(Replica.id, "replica-stored");
      assert.equal(Replica.token, "token-stored");
    });
  });

  describe("current()", () => {
    it("answers the pair in use", () => {
      Replica.adopt(stored);

      assert.deepStrictEqual(Replica.current(), {
        id: "replica-stored",
        token: "token-stored",
      });
    });
  });

  describe("offer()", () => {
    it("adopts the offered pair when none is in use", () => {
      Replica.offer(fresh);

      assert.equal(Replica.id, "replica-fresh");
      assert.equal(Replica.token, "token-fresh");
    });

    it("keeps the pair in use and remembers the offer", () => {
      Replica.adopt(stored);
      Replica.offer(fresh);

      assert.equal(Replica.id, "replica-stored");
      assert.deepStrictEqual(Replica.fresh, fresh);
    });

    it("keeps nothing in use when the page emitted no pair", () => {
      Replica.offer({id: undefined, token: undefined});

      assert.isNull(Replica.id);
      assert.isNull(Replica.token);
    });
  });

  describe("refresh()", () => {
    it("switches to the offered pair and answers true", () => {
      Replica.adopt(stored);
      Replica.offer(fresh);

      assert.isTrue(Replica.refresh());
      assert.equal(Replica.id, "replica-fresh");
      assert.equal(Replica.token, "token-fresh");
    });

    it("answers false when the offered pair is already in use", () => {
      Replica.offer(fresh);

      assert.isFalse(Replica.refresh());
      assert.equal(Replica.id, "replica-fresh");
    });

    it("answers false when nothing was offered", () => {
      Replica.adopt(stored);

      assert.isFalse(Replica.refresh());
      assert.equal(Replica.id, "replica-stored");
    });
  });

  describe("requestMint()", () => {
    it("marks the tab as waiting for a pair", () => {
      Replica.requestMint();

      assert.isTrue(Replica.awaitingMint);
    });
  });

  describe("refuseMint()", () => {
    it("ends the asking for good", () => {
      Replica.requestMint();
      Replica.refuseMint();

      assert.isFalse(Replica.awaitingMint);
      assert.isTrue(Replica.mintRefused);
    });

    it("does nothing in a tab that wasn't asking", () => {
      Replica.refuseMint();

      assert.isFalse(Replica.mintRefused);
    });

    // Two handshakes can overlap, both showing the stored pair.
    it("ignores a refusal of a pair the tab has moved on from", () => {
      Replica.offer({id: "r-page", token: "statement-page"});
      Replica.adopt({id: "r-stored", token: "statement-stored"});
      Replica.requestMint();

      Replica.refuseMint("r-stored");
      Replica.refuseMint("r-stored");

      assert.equal(Replica.id, "r-page");
      assert.isTrue(Replica.awaitingMint);
      assert.isFalse(Replica.mintRefused);

      Replica.refuseMint("r-page");

      assert.isFalse(Replica.awaitingMint);
      assert.isTrue(Replica.mintRefused);
    });

    // The refused pair can be a stored one from a session that has ended.
    it("gives the page's own pair a turn first", () => {
      Replica.offer({id: "r-page", token: "statement-page"});
      Replica.adopt({id: "r-stored", token: "statement-stored"});
      Replica.requestMint();

      Replica.refuseMint();

      assert.equal(Replica.id, "r-page");
      assert.isTrue(Replica.awaitingMint);
      assert.isFalse(Replica.mintRefused);

      Replica.refuseMint();

      assert.isFalse(Replica.awaitingMint);
      assert.isTrue(Replica.mintRefused);
    });

    it("can still take a pair afterwards", () => {
      Replica.requestMint();
      Replica.refuseMint();

      assert.isTrue(Replica.takeMinted({id: "r-minted", token: "statement"}));

      assert.equal(Replica.id, "r-minted");
      assert.isFalse(Replica.mintRefused);
      assert.isTrue(Replica.minted);
    });
  });

  describe("withoutIdentity()", () => {
    it("is false for a tab with a pair to send under", () => {
      assert.isFalse(Replica.withoutIdentity());
    });

    it("is true while asking", () => {
      Replica.requestMint();

      assert.isTrue(Replica.withoutIdentity());
    });

    it("is true once refused", () => {
      Replica.requestMint();
      Replica.refuseMint();

      assert.isTrue(Replica.withoutIdentity());
    });

    it("is false once the pair has arrived", () => {
      Replica.requestMint();
      Replica.takeMinted({id: "r-minted", token: "statement"});

      assert.isFalse(Replica.withoutIdentity());
    });
  });

  describe("takeMinted()", () => {
    const minted = {id: "replica-minted", token: "token-minted"};

    it("puts the pair in use and stops waiting", () => {
      Replica.offer(fresh);
      Replica.requestMint();

      assert.isTrue(Replica.takeMinted(minted));
      assert.deepStrictEqual(Replica.current(), minted);
      assert.isFalse(Replica.awaitingMint);
    });

    // A browser can hand the same cached page to another tab, so the page's pair is not safe to go
    // back to.
    it("leaves refresh() no way back to the page's pair", () => {
      Replica.offer(fresh);
      Replica.requestMint();
      Replica.takeMinted(minted);

      assert.isFalse(Replica.refresh());
      assert.deepStrictEqual(Replica.current(), minted);
    });

    // Two handshakes can be out at once, and numbers may already be spent under the first pair.
    it("passes over a pair when the tab is not waiting for one", () => {
      Replica.offer(fresh);

      assert.isFalse(Replica.takeMinted(minted));
      assert.deepStrictEqual(Replica.current(), fresh);
    });

    it("keeps waiting when the handshake brought no pair", () => {
      Replica.offer(fresh);
      Replica.requestMint();

      assert.isFalse(Replica.takeMinted(undefined));
      assert.isTrue(Replica.awaitingMint);
      assert.deepStrictEqual(Replica.current(), fresh);
    });
  });

  it("reset() stops waiting for a pair", () => {
    Replica.requestMint();
    Replica.reset();

    assert.isFalse(Replica.awaitingMint);
  });
});
