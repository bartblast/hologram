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
