"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import FocusEvent from "../../../assets/js/events/focus_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("FocusEvent", () => {
  const event = {};

  it("buildOperationParam()", () => {
    assert.deepStrictEqual(FocusEvent.buildOperationParam(event), Type.map());
  });

  it("isEventIgnored()", () => {
    assert.isFalse(FocusEvent.isEventIgnored(event));
  });
});
