"use strict";

import {assert, defineRuntimeGlobals} from "../support/helpers.mjs";

import TransitionEvent from "../../../assets/js/events/transition_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

describe("TransitionEvent", () => {
  const event = {};

  it("buildEventParam()", () => {
    assert.deepStrictEqual(TransitionEvent.buildEventParam(event), Type.map());
  });

  it("isEventIgnored()", () => {
    assert.isFalse(TransitionEvent.isEventIgnored(event));
  });
});
