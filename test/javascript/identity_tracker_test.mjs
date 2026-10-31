"use strict";

import {assert, defineRuntimeGlobals, UUID_REGEX} from "./support/helpers.mjs";

import IdentityTracker from "../../assets/js/identity_tracker.mjs";

defineRuntimeGlobals();

describe("IdentityTracker", () => {
  beforeEach(() => IdentityTracker.init("tag-1"));

  afterEach(() => {
    IdentityTracker.documentPeriod = null;
    IdentityTracker.period = null;
    IdentityTracker.tag = null;
  });

  describe("init()", () => {
    it("starts a period for the identity the document was rendered for", () => {
      assert.equal(IdentityTracker.tag, "tag-1");
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
      IdentityTracker.observe("tag-2");

      assert.isFalse(IdentityTracker.isCurrent(endedPeriod));
    });

    // Before any period has started, no period is the current one either.
    it("is false for no period", () => {
      IdentityTracker.period = null;

      assert.isFalse(IdentityTracker.isCurrent(null));
      assert.isFalse(IdentityTracker.isCurrent(undefined));
    });
  });

  describe("isCurrentTag()", () => {
    it("is true for the tag of the latest response", () => {
      assert.isTrue(IdentityTracker.isCurrentTag("tag-1"));
    });

    it("is false for another tag", () => {
      assert.isFalse(IdentityTracker.isCurrentTag("tag-2"));
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

      assert.equal(IdentityTracker.observe("tag-1"), period);
      assert.equal(IdentityTracker.period, period);
    });

    it("starts a new period when the tag changes", () => {
      const period = IdentityTracker.period;

      const newPeriod = IdentityTracker.observe("tag-2");

      assert.notEqual(newPeriod, period);
      assert.match(newPeriod, UUID_REGEX);
      assert.equal(IdentityTracker.period, newPeriod);
      assert.equal(IdentityTracker.tag, "tag-2");
      assert.equal(IdentityTracker.documentPeriod, period);
    });

    // A logout and a login back as the same user give the same tag, and what the identity in
    // between put in the client's state must not count as the first one's.
    it("starts a new period when the tag changes back", () => {
      const firstPeriod = IdentityTracker.period;
      const secondPeriod = IdentityTracker.observe("tag-2");
      const thirdPeriod = IdentityTracker.observe("tag-1");

      assert.notEqual(thirdPeriod, firstPeriod);
      assert.notEqual(thirdPeriod, secondPeriod);
    });

    it("keeps the period when the response carries no tag", () => {
      const period = IdentityTracker.period;

      assert.equal(IdentityTracker.observe(null), period);
      assert.equal(IdentityTracker.observe(undefined), period);
      assert.equal(IdentityTracker.tag, "tag-1");
    });
  });

  describe("observeResponse()", () => {
    it("reads the tag from the response's header", () => {
      const response = {
        headers: new Headers({"hologram-identity-tag": "tag-2"}),
      };

      const period = IdentityTracker.observeResponse(response);

      assert.equal(IdentityTracker.tag, "tag-2");
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

  describe("tagFor()", () => {
    it("is the tag of the identity while the period lasts", () => {
      assert.equal(IdentityTracker.tagFor(IdentityTracker.period), "tag-1");
    });

    // The state can hold what two identities put in it.
    it("is null once the period has ended", () => {
      const endedPeriod = IdentityTracker.period;
      IdentityTracker.observe("tag-2");

      assert.isNull(IdentityTracker.tagFor(endedPeriod));
    });
  });
});
