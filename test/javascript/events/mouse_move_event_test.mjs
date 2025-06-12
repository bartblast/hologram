"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import MouseMoveEvent from "../../../assets/js/events/mouse_move_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("MouseMoveEvent", () => {
  it("buildOperationParam()", () => {
    const event = {pageX: 1, pageY: 2};
    const result = MouseMoveEvent.buildOperationParam(event);

    assert.deepStrictEqual(
      result,
      Type.map([
        [Type.atom("page_x"), Type.float(1)],
        [Type.atom("page_y"), Type.float(2)],
      ]),
    );
  });

  it("isEventIgnored()", () => {
    assert.isFalse(MouseMoveEvent.isEventIgnored({}));
  });
});
