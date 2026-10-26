"use strict";

import {assert, defineRuntimeGlobals} from "../support/helpers.mjs";

import FocusEvent from "../../../assets/js/events/focus_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

describe("FocusEvent", () => {
  const event = {};

  it("buildOperationParam()", () => {
    assert.deepStrictEqual(FocusEvent.buildOperationParam(event), Type.map());
  });

  describe("isEventIgnored()", () => {
    afterEach(() => {
      FocusEvent.isRuntimeFocusChange = false;
    });

    it("a focus change the user made", () => {
      assert.isFalse(FocusEvent.isEventIgnored(event));
    });

    it("a focus change the runtime made", () => {
      FocusEvent.isRuntimeFocusChange = true;

      assert.isTrue(FocusEvent.isEventIgnored(event));
    });
  });
});
