"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  sinon,
} from "../support/helpers.mjs";

import DragEvent, {
  DropTargetDragEvent,
} from "../../../assets/js/events/drag_event.mjs";
import MouseEvent from "../../../assets/js/events/mouse_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("DragEvent", () => {
  describe("default behavior", () => {
    it("allows default browser behavior for regular drag events", () => {
      assert.isTrue(DragEvent.isDefaultAllowed);
    });

    it("prevents default browser behavior for drop-target drag events", () => {
      assert.isFalse(DropTargetDragEvent.isDefaultAllowed);
    });
  });

  describe("buildOperationParam()", () => {
    it("serializes mouse and data transfer metadata", () => {
      const event = {
        altKey: true,
        button: 0,
        buttons: 1,
        clientX: 10,
        clientY: 20,
        ctrlKey: false,
        dataTransfer: {
          dropEffect: "copy",
          effectAllowed: "copyMove",
          items: [
            {kind: "string", type: "text/plain"},
            {kind: "file", type: "image/png"},
          ],
          types: ["text/plain", "Files"],
        },
        metaKey: true,
        movementX: 5,
        movementY: 15,
        offsetX: 30,
        offsetY: 40,
        pageX: 1,
        pageY: 2,
        screenX: 100,
        screenY: 200,
        shiftKey: false,
      };

      const result = DragEvent.buildOperationParam(event);

      const expected = Type.map([
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
        [Type.atom("alt_key"), Type.boolean(true)],
        [Type.atom("button"), Type.integer(0)],
        [Type.atom("buttons"), Type.integer(1)],
        [Type.atom("ctrl_key"), Type.boolean(false)],
        [
          Type.atom("data_transfer"),
          Type.map([
            [Type.atom("drop_effect"), Type.bitstring("copy")],
            [Type.atom("effect_allowed"), Type.bitstring("copyMove")],
            [
              Type.atom("types"),
              Type.list([
                Type.bitstring("text/plain"),
                Type.bitstring("Files"),
              ]),
            ],
            [
              Type.atom("items"),
              Type.list([
                Type.map([
                  [Type.atom("kind"), Type.bitstring("string")],
                  [Type.atom("type"), Type.bitstring("text/plain")],
                ]),
                Type.map([
                  [Type.atom("kind"), Type.bitstring("file")],
                  [Type.atom("type"), Type.bitstring("image/png")],
                ]),
              ]),
            ],
          ]),
        ],
        [Type.atom("meta_key"), Type.boolean(true)],
        [Type.atom("shift_key"), Type.boolean(false)],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("serializes missing data transfer as nil", () => {
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

      const result = DragEvent.buildOperationParam(event);
      const dataTransfer =
        result.data[Type.encodeMapKey(Type.atom("data_transfer"))][1];

      assert.deepStrictEqual(dataTransfer, Type.nil());
    });
  });

  it("isEventIgnored()", () => {
    const mouseEventIsEventIgnoredStub = sinon
      .stub(MouseEvent, "isEventIgnored")
      .callsFake(() => null);

    try {
      DragEvent.isEventIgnored("dummy_event");

      sinon.assert.calledOnceWithExactly(
        mouseEventIsEventIgnoredStub,
        "dummy_event",
      );
    } finally {
      MouseEvent.isEventIgnored.restore();
    }
  });
});
