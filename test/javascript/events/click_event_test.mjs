"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import ClickEvent from "../../../assets/js/events/click_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("ClickEvent", () => {
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
      pointerType: "mouse",
      screenX: 100,
      screenY: 200,
    };

    const result = ClickEvent.buildOperationParam(event);

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
        [Type.atom("pointer_type"), Type.atom("mouse")],
        [Type.atom("screen_x"), Type.float(100)],
        [Type.atom("screen_y"), Type.float(200)],
      ]),
    );
  });

  describe("isEventIgnored()", () => {
    it("no special keys are pressed, main button is pressed", () => {
      const event = {
        ctrlKey: false,
        metaKey: false,
        shiftKey: false,
        button: 0,
      };

      assert.isFalse(ClickEvent.isEventIgnored(event));
    });

    it("no special keys are pressed, auxiliary button is pressed", () => {
      const event = {
        ctrlKey: false,
        metaKey: false,
        shiftKey: false,
        button: 1,
      };

      assert.isTrue(ClickEvent.isEventIgnored(event));
    });

    it("ctrl key is pressed, main button is pressed", () => {
      const event = {ctrlKey: true, metaKey: false, shiftKey: false, button: 0};
      assert.isTrue(ClickEvent.isEventIgnored(event));
    });

    it("meta key is pressed, main button is pressed", () => {
      const event = {ctrlKey: false, metaKey: true, shiftKey: false, button: 0};
      assert.isTrue(ClickEvent.isEventIgnored(event));
    });

    it("shift key is pressed, main button is pressed", () => {
      const event = {ctrlKey: false, metaKey: false, shiftKey: true, button: 0};
      assert.isTrue(ClickEvent.isEventIgnored(event));
    });
  });
});
