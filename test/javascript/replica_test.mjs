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
});
