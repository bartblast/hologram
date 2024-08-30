"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import TransitionEvent from "../../../assets/js/events/transition_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("TransitionEvent", () => {
  const event = {};

  it("buildOperationParam()", () => {
    assert.deepStrictEqual(
      TransitionEvent.buildOperationParam(event),
      Type.map(),
    );
  });

  it("isEventIgnored()", () => {
    assert.isFalse(TransitionEvent.isEventIgnored(event));
  });
});
