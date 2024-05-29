"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  sinon,
} from "../support/helpers.mjs";

import MouseEvent from "../../../assets/js/events/mouse_event.mjs";
import PointerEvent from "../../../assets/js/events/pointer_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("PointerEvent", () => {
  describe("buildOperationParam()", () => {
    it("known pointer type", () => {
      const event = {pageX: 1, pageY: 2, pointerType: "mouse"};
      const result = PointerEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.atom("page_x"), Type.float(1)],
          [Type.atom("page_y"), Type.float(2)],
          [Type.atom("pointer_type"), Type.atom("mouse")],
        ]),
      );
    });

    it("unknown pointer type", () => {
      const event = {pageX: 1, pageY: 2, pointerType: ""};
      const result = PointerEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.atom("page_x"), Type.float(1)],
          [Type.atom("page_y"), Type.float(2)],
          [Type.atom("pointer_type"), Type.nil()],
        ]),
      );
    });
  });

  it("isEventIgnored()", () => {
    const mouseEventIsEventIgnoredStub = sinon
      .stub(MouseEvent, "isEventIgnored")
      .callsFake(() => null);

    PointerEvent.isEventIgnored("dummy_event");

    sinon.assert.calledOnceWithExactly(
      mouseEventIsEventIgnoredStub,
      "dummy_event",
    );

    MouseEvent.isEventIgnored.restore();
  });
});
