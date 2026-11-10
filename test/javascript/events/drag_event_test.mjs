"use strict";

import {assert, defineRuntimeGlobals, sinon} from "../support/helpers.mjs";

import DragEvent from "../../../assets/js/events/drag_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

const mouseDetails = [
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
];

const mouseFields = {
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

// A DataTransfer holding the given data by type, with an item per type.
function buildDataTransfer({
  data = {},
  dropEffect = "none",
  effectAllowed = "uninitialized",
  items = null,
  types = null,
} = {}) {
  return {
    dropEffect,
    effectAllowed,
    getData: sinon.spy((type) => data[type] ?? ""),
    items: items ?? Object.keys(data).map((type) => ({kind: "string", type})),
    types: types ?? Object.keys(data),
  };
}

function buildEffectsAllowed(copy, link, move) {
  return Type.map([
    [Type.atom("copy"), Type.boolean(copy)],
    [Type.atom("link"), Type.boolean(link)],
    [Type.atom("move"), Type.boolean(move)],
  ]);
}

function buildEvent(type, dataTransfer) {
  return {...mouseFields, type, dataTransfer};
}

function buildExpected({
  data = Type.map(),
  dropEffect = "none",
  effectsAllowed = buildEffectsAllowed(true, true, true),
  items = [],
  types = [],
} = {}) {
  return Type.map([
    ...mouseDetails,
    [
      Type.atom("data_transfer"),
      Type.map([
        [Type.atom("data"), data],
        [Type.atom("drop_effect"), Type.atom(dropEffect)],
        [Type.atom("effects_allowed"), effectsAllowed],
        [Type.atom("files"), Type.list()],
        [
          Type.atom("items"),
          Type.list(
            items.map(([kind, type]) =>
              Type.map([
                [Type.atom("kind"), Type.atom(kind)],
                [Type.atom("type"), Type.bitstring(type)],
              ]),
            ),
          ),
        ],
        [
          Type.atom("types"),
          Type.list(types.map((type) => Type.bitstring(type))),
        ],
      ]),
    ],
  ]);
}

describe("DragEvent", () => {
  it("isDefaultAllowed", () => {
    assert.isTrue(DragEvent.isDefaultAllowed);
  });

  describe("buildOperationParam()", () => {
    it("reads the data on dragstart", () => {
      const dataTransfer = buildDataTransfer({
        data: {"text/plain": "Buy milk", "application/x-task": "42"},
        effectAllowed: "move",
      });

      const result = DragEvent.buildOperationParam(
        buildEvent("dragstart", dataTransfer),
      );

      const expected = buildExpected({
        data: Type.map([
          [Type.bitstring("application/x-task"), Type.bitstring("42")],
          [Type.bitstring("text/plain"), Type.bitstring("Buy milk")],
        ]),
        effectsAllowed: buildEffectsAllowed(false, false, true),
        items: [
          ["string", "text/plain"],
          ["string", "application/x-task"],
        ],
        types: ["text/plain", "application/x-task"],
      });

      assert.deepStrictEqual(result, expected);
    });

    it("reads the data on drop", () => {
      const dataTransfer = buildDataTransfer({
        data: {"text/plain": "Buy milk"},
        dropEffect: "move",
        effectAllowed: "move",
      });

      const result = DragEvent.buildOperationParam(
        buildEvent("drop", dataTransfer),
      );

      const expected = buildExpected({
        data: Type.map([
          [Type.bitstring("text/plain"), Type.bitstring("Buy milk")],
        ]),
        dropEffect: "move",
        effectsAllowed: buildEffectsAllowed(false, false, true),
        items: [["string", "text/plain"]],
        types: ["text/plain"],
      });

      assert.deepStrictEqual(result, expected);
    });

    for (const type of [
      "drag",
      "dragend",
      "dragenter",
      "dragleave",
      "dragover",
    ]) {
      it(`shows the types but not the data on ${type}`, () => {
        const dataTransfer = buildDataTransfer({
          data: {"text/plain": "Buy milk"},
        });

        const result = DragEvent.buildOperationParam(
          buildEvent(type, dataTransfer),
        );

        const expected = buildExpected({
          items: [["string", "text/plain"]],
          types: ["text/plain"],
        });

        assert.deepStrictEqual(result, expected);
        sinon.assert.notCalled(dataTransfer.getData);
      });
    }

    it("doesn't read the Files type as data", () => {
      const dataTransfer = buildDataTransfer({
        data: {"text/plain": "notes.txt"},
        items: [
          {kind: "string", type: "text/plain"},
          {kind: "file", type: "text/plain"},
        ],
        types: ["text/plain", "Files"],
      });

      const result = DragEvent.buildOperationParam(
        buildEvent("drop", dataTransfer),
      );

      const expected = buildExpected({
        data: Type.map([
          [Type.bitstring("text/plain"), Type.bitstring("notes.txt")],
        ]),
        items: [
          ["string", "text/plain"],
          ["file", "text/plain"],
        ],
        types: ["text/plain", "Files"],
      });

      assert.deepStrictEqual(result, expected);
      sinon.assert.calledOnceWithExactly(dataTransfer.getData, "text/plain");
    });

    it("leaves out Hologram's placeholder type", () => {
      const dataTransfer = buildDataTransfer({
        data: {"application/x-hologram": "hologram"},
      });

      const result = DragEvent.buildOperationParam(
        buildEvent("drop", dataTransfer),
      );

      assert.deepStrictEqual(result, buildExpected());
    });

    it("reads an event with no DataTransfer as a drag with nothing on it", () => {
      const result = DragEvent.buildOperationParam(buildEvent("drop", null));

      assert.deepStrictEqual(result, buildExpected());
    });

    for (const dropEffect of ["copy", "link", "move", "none"]) {
      it(`reads the ${dropEffect} drop effect`, () => {
        const result = DragEvent.buildOperationParam(
          buildEvent("dragover", buildDataTransfer({dropEffect})),
        );

        assert.deepStrictEqual(result, buildExpected({dropEffect}));
      });
    }

    for (const [effectAllowed, copy, link, move] of [
      ["all", true, true, true],
      ["copy", true, false, false],
      ["copyLink", true, true, false],
      ["copyMove", true, false, true],
      ["link", false, true, false],
      ["linkMove", false, true, true],
      ["move", false, false, true],
      ["none", false, false, false],
      ["uninitialized", true, true, true],
    ]) {
      it(`reads the ${effectAllowed} allowed effects`, () => {
        const result = DragEvent.buildOperationParam(
          buildEvent("dragover", buildDataTransfer({effectAllowed})),
        );

        const expected = buildExpected({
          effectsAllowed: buildEffectsAllowed(copy, link, move),
        });

        assert.deepStrictEqual(result, expected);
      });
    }

    it("reads an allowed effects value no browser reports, like an Object.prototype key, as every effect", () => {
      const result = DragEvent.buildOperationParam(
        buildEvent("dragover", buildDataTransfer({effectAllowed: "toString"})),
      );

      assert.deepStrictEqual(result, buildExpected());
    });
  });

  it("isEventIgnored()", () => {
    assert.isFalse(DragEvent.isEventIgnored(buildEvent("dragover", null)));
  });
});
