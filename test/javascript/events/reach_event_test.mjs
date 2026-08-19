"use strict";

import {assert, defineRuntimeGlobals} from "../support/helpers.mjs";

import ReachEvent from "../../../assets/js/events/reach_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

describe("ReachEvent", () => {
  it("buildEventParam()", () => {
    const result = ReachEvent.buildEventParam({target: {}});

    assert.deepStrictEqual(result, Type.map());
  });

  it("isEventIgnored()", () => {
    assert.isFalse(ReachEvent.isEventIgnored({target: {}}));
  });
});
