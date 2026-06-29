"use strict";

import {assert} from "./support/helpers.mjs";

import Once from "../../assets/js/once.mjs";

describe("Once", () => {
  describe("hasFired() / markFired()", () => {
    it("a slot has not fired before it is marked", () => {
      const element = {};

      assert.isFalse(Once.hasFired(element, "slot"));
    });

    it("a slot has fired after it is marked", () => {
      const element = {};

      Once.markFired(element, "slot");

      assert.isTrue(Once.hasFired(element, "slot"));
    });

    it("marking a slot a second time leaves it fired", () => {
      const element = {};

      Once.markFired(element, "slot");
      Once.markFired(element, "slot");

      assert.isTrue(Once.hasFired(element, "slot"));
    });

    it("tracks fired-state independently per slot on the same element", () => {
      const element = {};

      Once.markFired(element, "slot-a");

      assert.isTrue(Once.hasFired(element, "slot-a"));
      assert.isFalse(Once.hasFired(element, "slot-b"));
    });

    it("tracks fired-state independently per element for the same slot", () => {
      const elementA = {};
      const elementB = {};

      Once.markFired(elementA, "slot");

      assert.isTrue(Once.hasFired(elementA, "slot"));
      assert.isFalse(Once.hasFired(elementB, "slot"));
    });
  });
});
