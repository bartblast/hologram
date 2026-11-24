"use strict";

import {assert, defineRuntimeGlobals, UUID_REGEX} from "./support/helpers.mjs";

import IdentityTracker from "../../assets/js/identity_tracker.mjs";

defineRuntimeGlobals();

describe("IdentityTracker", () => {
  beforeEach(() => IdentityTracker.init("1.tag-1"));

  afterEach(() => {
    IdentityTracker.documentPeriod = null;
    IdentityTracker.period = null;
    IdentityTracker.periods = new Set();
    IdentityTracker.tag = null;
  });

  describe("init()", () => {
    it("starts a period for the identity the document was rendered for", () => {
      assert.equal(IdentityTracker.tag, "1.tag-1");
      assert.match(IdentityTracker.period, UUID_REGEX);
      assert.equal(IdentityTracker.documentPeriod, IdentityTracker.period);
    });

    it("knows no identity when the document names none", () => {
      IdentityTracker.init(undefined);

      assert.isNull(IdentityTracker.tag);
      assert.match(IdentityTracker.period, UUID_REGEX);
    });
  });

  describe("isCurrent()", () => {
    it("is true for the period that lasts now", () => {
      assert.isTrue(IdentityTracker.isCurrent(IdentityTracker.period));
    });

    it("is false for a period that has ended", () => {
      const endedPeriod = IdentityTracker.period;
      IdentityTracker.observe("2.tag-2");

      assert.isFalse(IdentityTracker.isCurrent(endedPeriod));
    });

    // Before any period has started, no period is the current one either.
    it("is false for no period", () => {
      IdentityTracker.period = null;

      assert.isFalse(IdentityTracker.isCurrent(null));
      assert.isFalse(IdentityTracker.isCurrent(undefined));
    });
  });

  describe("isOwnPeriod()", () => {
    it("is true for the period the document started in", () => {
      assert.isTrue(
        IdentityTracker.isOwnPeriod(IdentityTracker.documentPeriod),
      );
    });

    it("is true for a later period, lasting or ended", () => {
      const secondPeriod = IdentityTracker.observe("2.tag-2");
      const thirdPeriod = IdentityTracker.observe("3.tag-3");

      assert.isTrue(IdentityTracker.isOwnPeriod(secondPeriod));
      assert.isTrue(IdentityTracker.isOwnPeriod(thirdPeriod));
    });

    // A period another document started, named by a snapshot that document took.
    it("is false for a period this document never started", () => {
      assert.isFalse(IdentityTracker.isOwnPeriod("period-of-another-document"));
    });

    it("is false for no period", () => {
      assert.isFalse(IdentityTracker.isOwnPeriod(null));
      assert.isFalse(IdentityTracker.isOwnPeriod(undefined));
    });
  });

  describe("isCurrentTag()", () => {
    it("is true for the tag of the latest response", () => {
      assert.isTrue(IdentityTracker.isCurrentTag("1.tag-1"));
    });

    it("is false for another tag", () => {
      assert.isFalse(IdentityTracker.isCurrentTag("2.tag-2"));
    });

    it("is false for no tag, even when no tag is known", () => {
      IdentityTracker.init(undefined);

      assert.isFalse(IdentityTracker.isCurrentTag(null));
      assert.isFalse(IdentityTracker.isCurrentTag(undefined));
    });
  });

  describe("observe()", () => {
    it("keeps the period while the tag stays the same", () => {
      const period = IdentityTracker.period;

      assert.equal(IdentityTracker.observe("1.tag-1"), period);
      assert.equal(IdentityTracker.period, period);
    });

    it("starts a new period when the tag changes", () => {
      const period = IdentityTracker.period;

      const newPeriod = IdentityTracker.observe("2.tag-2");

      assert.notEqual(newPeriod, period);
      assert.match(newPeriod, UUID_REGEX);
      assert.equal(IdentityTracker.period, newPeriod);
      assert.equal(IdentityTracker.tag, "2.tag-2");
      assert.equal(IdentityTracker.documentPeriod, period);
    });

    // A logout and a login back as the same user give the same tag, and what the identity in
    // between put in the client's state must not count as the first one's.
    it("starts a new period when the tag changes back", () => {
      const firstPeriod = IdentityTracker.period;
      const secondPeriod = IdentityTracker.observe("2.tag-2");
      const thirdPeriod = IdentityTracker.observe("1.tag-1");

      assert.notEqual(thirdPeriod, firstPeriod);
      assert.notEqual(thirdPeriod, secondPeriod);
    });

    it("keeps the period when the response carries no tag", () => {
      const period = IdentityTracker.period;

      assert.equal(IdentityTracker.observe(null), period);
      assert.equal(IdentityTracker.observe(undefined), period);
      assert.equal(IdentityTracker.tag, "1.tag-1");
    });
  });

  describe("observeResponse()", () => {
    it("reads the tag from the response's header", () => {
      const response = {
        headers: new Headers({"hologram-identity-tag": "2.tag-2"}),
      };

      const period = IdentityTracker.observeResponse(response);

      assert.equal(IdentityTracker.tag, "2.tag-2");
      assert.equal(period, IdentityTracker.period);
    });

    it("keeps the period when the response has no tag header", () => {
      const period = IdentityTracker.period;

      assert.equal(
        IdentityTracker.observeResponse({headers: new Headers()}),
        period,
      );
    });
  });

  describe("isBehind()", () => {
    beforeEach(() => {
      IdentityTracker.init("5.tag");
    });

    it("is true for another identity with an older stamp", () => {
      assert.isTrue(IdentityTracker.isBehind("4.other"));
    });

    // Neither of two changes made at one moment can be taken for the later one.
    it("is true for another identity with the same stamp", () => {
      assert.isTrue(IdentityTracker.isBehind("5.other"));
    });

    it("is false for a newer stamp", () => {
      assert.isFalse(IdentityTracker.isBehind("6.other"));
    });

    it("is false for the current tag", () => {
      assert.isFalse(IdentityTracker.isBehind("5.tag"));
    });

    it("is false for no tag", () => {
      assert.isFalse(IdentityTracker.isBehind(null));
      assert.isFalse(IdentityTracker.isBehind(undefined));
    });

    it("is false while no tag is known", () => {
      IdentityTracker.init(null);

      assert.isFalse(IdentityTracker.isBehind("1.tag"));
    });

    it("compares stamps as numbers", () => {
      IdentityTracker.init("9.tag");

      assert.isFalse(IdentityTracker.isBehind("10.other"));
    });
  });

  describe("isOlder()", () => {
    beforeEach(() => {
      IdentityTracker.init("5.tag");
    });

    it("is true for another identity with an older stamp", () => {
      assert.isTrue(IdentityTracker.isOlder("4.other"));
    });

    it("is false for another identity with the same stamp", () => {
      assert.isFalse(IdentityTracker.isOlder("5.other"));
    });

    it("is false for a newer stamp", () => {
      assert.isFalse(IdentityTracker.isOlder("6.other"));
    });

    // A cookie that was cleared isn't a cookie that hasn't caught up.
    it("is false for the tag of a request with no session", () => {
      assert.isFalse(IdentityTracker.isOlder("none.other"));
    });
  });

  describe("observeResponse()", () => {
    const responseWith = (tag) => ({
      headers: new Headers(tag === null ? {} : {"hologram-identity-tag": tag}),
    });

    beforeEach(() => {
      IdentityTracker.init("5.tag");
    });

    it("takes in a newer tag", () => {
      const period = IdentityTracker.observeResponse(responseWith("6.other"));

      assert.equal(IdentityTracker.tag, "6.other");
      assert.equal(period, IdentityTracker.period);
    });

    it("answers the current period for the current tag", () => {
      const period = IdentityTracker.period;

      assert.equal(
        IdentityTracker.observeResponse(responseWith("5.tag")),
        period,
      );
    });

    it("answers the current period for a response naming no tag", () => {
      const period = IdentityTracker.period;

      assert.equal(IdentityTracker.observeResponse(responseWith(null)), period);
    });

    for (const [name, tag] of [
      ["an older", "4.other"],
      ["a tied", "5.other"],
    ]) {
      it(`leaves the identity alone for ${name} tag`, () => {
        const period = IdentityTracker.period;

        IdentityTracker.observeResponse(responseWith(tag));

        assert.equal(IdentityTracker.tag, "5.tag");
        assert.equal(IdentityTracker.period, period);
      });

      it(`answers no period of this document for ${name} tag`, () => {
        const period = IdentityTracker.observeResponse(responseWith(tag));

        assert.equal(period, IdentityTracker.SUPERSEDED);
        assert.isFalse(IdentityTracker.isCurrent(period));
        assert.isFalse(IdentityTracker.isOwnPeriod(period));
      });
    }
  });

  describe("tagFor()", () => {
    it("is the tag of the identity while the period lasts", () => {
      assert.equal(IdentityTracker.tagFor(IdentityTracker.period), "1.tag-1");
    });

    // The state can hold what two identities put in it.
    it("is null once the period has ended", () => {
      const endedPeriod = IdentityTracker.period;
      IdentityTracker.observe("2.tag-2");

      assert.isNull(IdentityTracker.tagFor(endedPeriod));
    });
  });
});
