"use strict";

import {assert, defineRuntimeGlobals} from "../support/helpers.mjs";

import SelectEvent from "../../../assets/js/events/select_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

describe("SelectEvent", () => {
  const event = {
    target: {selectionEnd: 15, selectionStart: 6, value: "Hologram 1 Hologram"},
  };

  it("buildEventParam()", () => {
    const result = SelectEvent.buildEventParam(event);

    assert.deepStrictEqual(
      result,
      Type.map([[Type.atom("value"), Type.bitstring("am 1 Holo")]]),
    );
  });

  it("isEventIgnored()", () => {
    assert.isFalse(SelectEvent.isEventIgnored(event));
  });
});
