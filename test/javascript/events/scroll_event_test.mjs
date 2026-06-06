"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import ScrollEvent from "../../../assets/js/events/scroll_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("ScrollEvent", () => {
  it("buildOperationParam()", () => {
    const event = {target: {scrollLeft: 12, scrollTop: 34}};
    const result = ScrollEvent.buildOperationParam(event);

    assert.deepStrictEqual(
      result,
      Type.map([
        [Type.atom("scroll_left"), Type.float(12)],
        [Type.atom("scroll_top"), Type.float(34)],
      ]),
    );
  });

  it("isEventIgnored()", () => {
    assert.isFalse(ScrollEvent.isEventIgnored({}));
  });
});
