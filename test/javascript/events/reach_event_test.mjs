"use strict";

import {assert, defineRuntimeGlobals} from "../support/helpers.mjs";

import ReachEvent from "../../../assets/js/events/reach_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

describe("ReachEvent", () => {
  it("buildOperationParam()", () => {
    const result = ReachEvent.buildOperationParam({target: {}});

    assert.deepStrictEqual(result, Type.map());
  });

  it("isEventIgnored()", () => {
    assert.isFalse(ReachEvent.isEventIgnored({target: {}}));
  });
});
