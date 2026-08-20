"use strict";

import {assert, defineRuntimeGlobals} from "../support/helpers.mjs";

import InputEvent from "../../../assets/js/events/input_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

describe("InputEvent", () => {
  const event = {
    target: {tagName: "INPUT", type: "text", value: "abc"},
  };

  it("buildEventParam()", () => {
    const result = InputEvent.buildEventParam(event);

    assert.deepStrictEqual(
      result,
      Type.map([[Type.atom("value"), Type.bitstring("abc")]]),
    );
  });

  it("isEventIgnored()", () => {
    assert.isFalse(InputEvent.isEventIgnored(event));
  });
});
