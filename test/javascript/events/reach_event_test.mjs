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
    const result = ReachEvent.buildOperationParam({isIntersecting: true});

    assert.deepStrictEqual(result, Type.map());
  });

  describe("isEventIgnored()", () => {
    it("the edge is in view", () => {
      assert.isFalse(ReachEvent.isEventIgnored({isIntersecting: true}));
    });

    it("the edge is out of view", () => {
      assert.isTrue(ReachEvent.isEventIgnored({isIntersecting: false}));
    });
  });
});
