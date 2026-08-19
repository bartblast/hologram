"use strict";

import {assert, defineRuntimeGlobals} from "../support/helpers.mjs";

import FocusEvent from "../../../assets/js/events/focus_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

describe("FocusEvent", () => {
  const event = {};

  it("buildEventParam()", () => {
    assert.deepStrictEqual(FocusEvent.buildEventParam(event), Type.map());
  });

  it("isEventIgnored()", () => {
    assert.isFalse(FocusEvent.isEventIgnored(event));
  });
});
