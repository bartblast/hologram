"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import MouseEvent from "../../../assets/js/events/mouse_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("MouseEvent", () => {
  it("buildOperationParam()", () => {
    const event = {
      clientX: 10,
      clientY: 20,
      movementX: 5,
      movementY: 15,
      offsetX: 30,
      offsetY: 40,
      pageX: 1,
      pageY: 2,
      screenX: 100,
      screenY: 200,
    };

    const result = MouseEvent.buildOperationParam(event);

    assert.deepStrictEqual(
      result,
      Type.map([
        [Type.atom("client_x"), Type.float(10)],
        [Type.atom("client_y"), Type.float(20)],
        [Type.atom("movement_x"), Type.float(5)],
        [Type.atom("movement_y"), Type.float(15)],
        [Type.atom("offset_x"), Type.float(30)],
        [Type.atom("offset_y"), Type.float(40)],
        [Type.atom("page_x"), Type.float(1)],
        [Type.atom("page_y"), Type.float(2)],
        [Type.atom("screen_x"), Type.float(100)],
        [Type.atom("screen_y"), Type.float(200)],
      ]),
    );
  });

  it("isEventIgnored()", () => {
    assert.isFalse(MouseEvent.isEventIgnored({}));
  });
});
