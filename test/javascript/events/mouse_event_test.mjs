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
    const event = {pageX: 1, pageY: 2};
    const result = MouseEvent.buildOperationParam(event);

    assert.deepStrictEqual(
      result,
      Type.map([
        [Type.atom("page_x"), Type.float(1)],
        [Type.atom("page_y"), Type.float(2)],
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

      assert.isFalse(MouseEvent.isEventIgnored(event));
    });

    it("no special keys are pressed, auxiliary button is pressed", () => {
      const event = {
        ctrlKey: false,
        metaKey: false,
        shiftKey: false,
        button: 1,
      };

      assert.isTrue(MouseEvent.isEventIgnored(event));
    });

    it("ctrl key is pressed, main button is pressed", () => {
      const event = {ctrlKey: true, metaKey: false, shiftKey: false, button: 0};
      assert.isTrue(MouseEvent.isEventIgnored(event));
    });

    it("meta key is pressed, main button is pressed", () => {
      const event = {ctrlKey: false, metaKey: true, shiftKey: false, button: 0};
      assert.isTrue(MouseEvent.isEventIgnored(event));
    });

    it("shift key is pressed, main button is pressed", () => {
      const event = {ctrlKey: false, metaKey: false, shiftKey: true, button: 0};
      assert.isTrue(MouseEvent.isEventIgnored(event));
    });
  });
});
