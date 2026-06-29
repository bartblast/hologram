"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import ReachEvent from "../../../assets/js/events/reach_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("ReachEvent", () => {
  it("buildOperationParam()", () => {
    const result = ReachEvent.buildOperationParam({target: {}});

    assert.deepStrictEqual(result, Type.map());
  });

  describe("isEventIgnored()", () => {
    it("a scroll-edge fire is never ignored", () => {
      assert.isFalse(ReachEvent.isEventIgnored({target: {}}));
    });

    it("an arriving IntersectionObserver entry is not ignored", () => {
      assert.isFalse(ReachEvent.isEventIgnored({isIntersecting: true}));
    });

    it("a leaving IntersectionObserver entry is ignored", () => {
      assert.isTrue(ReachEvent.isEventIgnored({isIntersecting: false}));
    });
  });
});
