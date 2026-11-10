"use strict";

import {assert, defineRuntimeGlobals, sinon} from "../support/helpers.mjs";

import DragEvent from "../../../assets/js/events/drag_event.mjs";
import DroppedFileRegistry from "../../../assets/js/dropped_file_registry.mjs";
import Type from "../../../assets/js/type.mjs";
import Utils from "../../../assets/js/utils.mjs";

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
  files = [],
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
        [
          Type.atom("files"),
          Type.list(
            files.map((path) =>
              Type.struct("Hologram.File", [
                [Type.atom("path"), Type.bitstring(path)],
              ]),
            ),
          ),
        ],
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
    const folderPath = "/$hologram/drops/dummy_uuid";

    let randomUUIDStub;

    beforeEach(() => {
      randomUUIDStub = sinon
        .stub(Utils, "randomUUID")
        .callsFake(() => "dummy_uuid");
    });

    afterEach(() => {
      randomUUIDStub.restore();
      DroppedFileRegistry.entries = new Map();
    });

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
          {
            kind: "file",
            type: "text/plain",
            getAsFile: () => ({name: "notes.txt"}),
          },
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
        files: [`${folderPath}/notes.txt`],
        items: [
          ["string", "text/plain"],
          ["file", "text/plain"],
        ],
        types: ["text/plain", "Files"],
      });

      assert.deepStrictEqual(result, expected);
      sinon.assert.calledOnceWithExactly(dataTransfer.getData, "text/plain");
    });

    describe("files", () => {
      function fileItem(file, entry = undefined) {
        const item = {kind: "file", type: "", getAsFile: () => file};

        if (entry !== undefined) {
          item.webkitGetAsEntry = () => entry;
        }

        return item;
      }

      function dropFiles(items, event = null) {
        const dropEvent =
          event ??
          buildEvent("drop", buildDataTransfer({items, types: ["Files"]}));

        return DragEvent.buildOperationParam(dropEvent);
      }

      function expectedFiles(paths) {
        return buildExpected({
          files: paths,
          items: paths.map(() => ["file", ""]),
          types: ["Files"],
        });
      }

      it("names a dropped file by its path", () => {
        const file = {name: "notes.txt"};

        const result = dropFiles([fileItem(file)]);

        assert.deepStrictEqual(
          result,
          expectedFiles([`${folderPath}/notes.txt`]),
        );

        assert.deepStrictEqual(
          DroppedFileRegistry.entries,
          new Map([[`${folderPath}/notes.txt`, file]]),
        );
      });

      it("keeps the File when the store has no entry for it", () => {
        const file = {name: "notes.txt"};

        const result = dropFiles([fileItem(file, null)]);

        assert.deepStrictEqual(
          result,
          expectedFiles([`${folderPath}/notes.txt`]),
        );

        assert.deepStrictEqual(
          DroppedFileRegistry.entries,
          new Map([[`${folderPath}/notes.txt`, file]]),
        );
      });

      it("keeps the File of a file entry", () => {
        const file = {name: "notes.txt"};
        const entry = {isDirectory: false, name: "notes.txt"};

        const result = dropFiles([fileItem(file, entry)]);

        assert.deepStrictEqual(
          result,
          expectedFiles([`${folderPath}/notes.txt`]),
        );

        assert.deepStrictEqual(
          DroppedFileRegistry.entries,
          new Map([[`${folderPath}/notes.txt`, file]]),
        );
      });

      it("keeps the entry of a folder", () => {
        const entry = {isDirectory: true, name: "photos"};

        const result = dropFiles([fileItem({name: "photos"}, entry)]);

        assert.deepStrictEqual(result, expectedFiles([`${folderPath}/photos`]));

        assert.deepStrictEqual(
          DroppedFileRegistry.entries,
          new Map([[`${folderPath}/photos`, entry]]),
        );
      });

      it("skips a file item with no File", () => {
        const result = dropFiles([fileItem(null)]);

        assert.deepStrictEqual(
          result,
          buildExpected({items: [["file", ""]], types: ["Files"]}),
        );

        assert.deepStrictEqual(DroppedFileRegistry.entries, new Map());
      });

      it("gives each file a folder of its own, so files with the same name stay apart", () => {
        randomUUIDStub.onFirstCall().returns("uuid_1");
        randomUUIDStub.onSecondCall().returns("uuid_2");

        const firstFile = {name: "notes.txt"};
        const secondFile = {name: "notes.txt"};

        const result = dropFiles([fileItem(firstFile), fileItem(secondFile)]);

        assert.deepStrictEqual(
          result,
          expectedFiles([
            "/$hologram/drops/uuid_1/notes.txt",
            "/$hologram/drops/uuid_2/notes.txt",
          ]),
        );

        assert.deepStrictEqual(
          DroppedFileRegistry.entries,
          new Map([
            ["/$hologram/drops/uuid_1/notes.txt", firstFile],
            ["/$hologram/drops/uuid_2/notes.txt", secondFile],
          ]),
        );
      });

      it("gives every binding of one drop the same files", () => {
        randomUUIDStub.onFirstCall().returns("uuid_1");
        randomUUIDStub.onSecondCall().returns("uuid_2");

        const file = {name: "notes.txt"};

        const event = buildEvent(
          "drop",
          buildDataTransfer({items: [fileItem(file)], types: ["Files"]}),
        );

        const expected = expectedFiles(["/$hologram/drops/uuid_1/notes.txt"]);

        assert.deepStrictEqual(dropFiles(null, event), expected);
        assert.deepStrictEqual(dropFiles(null, event), expected);

        assert.deepStrictEqual(
          DroppedFileRegistry.entries,
          new Map([["/$hologram/drops/uuid_1/notes.txt", file]]),
        );
      });

      for (const type of [
        "drag",
        "dragend",
        "dragenter",
        "dragleave",
        "dragover",
        "dragstart",
      ]) {
        it(`carries no files on ${type}`, () => {
          const getAsFile = sinon.spy();

          const result = DragEvent.buildOperationParam(
            buildEvent(
              type,
              buildDataTransfer({
                items: [{kind: "file", type: "", getAsFile}],
                types: ["Files"],
              }),
            ),
          );

          assert.deepStrictEqual(
            result,
            buildExpected({items: [["file", ""]], types: ["Files"]}),
          );

          sinon.assert.notCalled(getAsFile);
        });
      }
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

  describe("isEventIgnored()", () => {
    let child, element, outside;

    beforeEach(() => {
      element = document.createElement("div");
      child = document.createElement("span");
      outside = document.createElement("p");

      element.appendChild(child);
      document.body.append(element, outside);
    });

    afterEach(() => {
      element.remove();
      outside.remove();
    });

    function buildCrossing(type, currentTarget, relatedTarget) {
      return {type, currentTarget, relatedTarget};
    }

    for (const type of ["dragenter", "dragleave"]) {
      describe(type, () => {
        it("is ignored when the relatedTarget is a child", () => {
          assert.isTrue(
            DragEvent.isEventIgnored(buildCrossing(type, element, child)),
          );
        });

        it("is ignored when the relatedTarget is the element itself", () => {
          assert.isTrue(
            DragEvent.isEventIgnored(buildCrossing(type, element, element)),
          );
        });

        it("fires when the relatedTarget is outside the element", () => {
          assert.isFalse(
            DragEvent.isEventIgnored(buildCrossing(type, element, outside)),
          );
        });

        it("fires when there's no relatedTarget", () => {
          assert.isFalse(
            DragEvent.isEventIgnored(buildCrossing(type, element, null)),
          );
        });

        it("is ignored on the document when the drag crosses between elements", () => {
          assert.isTrue(
            DragEvent.isEventIgnored(buildCrossing(type, document, outside)),
          );
        });

        it("fires on the document when the drag crosses the page's edge", () => {
          assert.isFalse(
            DragEvent.isEventIgnored(buildCrossing(type, document, null)),
          );
        });

        it("is ignored on the window when the drag crosses between elements", () => {
          assert.isTrue(
            DragEvent.isEventIgnored(buildCrossing(type, window, outside)),
          );
        });

        it("is ignored on the document when the relatedTarget was removed from the page", () => {
          const removed = document.createElement("p");

          assert.isTrue(
            DragEvent.isEventIgnored(buildCrossing(type, document, removed)),
          );
        });

        it("is ignored on the window when the relatedTarget was removed from the page", () => {
          const removed = document.createElement("p");

          assert.isTrue(
            DragEvent.isEventIgnored(buildCrossing(type, window, removed)),
          );
        });

        it("fires on the window when the drag crosses the page's edge", () => {
          assert.isFalse(
            DragEvent.isEventIgnored(buildCrossing(type, window, null)),
          );
        });
      });
    }

    for (const type of ["drag", "dragend", "dragover", "dragstart", "drop"]) {
      it(`fires a ${type} whatever its relatedTarget`, () => {
        assert.isFalse(
          DragEvent.isEventIgnored(buildCrossing(type, element, child)),
        );
      });
    }
  });

  describe("prepareEvent()", () => {
    it("puts the placeholder on a dragstart that carries no data", () => {
      const dataTransfer = {setData: sinon.spy(), types: []};

      DragEvent.prepareEvent(buildEvent("dragstart", dataTransfer));

      sinon.assert.calledOnceWithExactly(
        dataTransfer.setData,
        "application/x-hologram",
        "hologram",
      );
    });

    it("leaves a dragstart that carries data alone", () => {
      const dataTransfer = {setData: sinon.spy(), types: ["text/plain"]};

      DragEvent.prepareEvent(buildEvent("dragstart", dataTransfer));

      sinon.assert.notCalled(dataTransfer.setData);
    });

    it("doesn't throw on a dragstart with no DataTransfer", () => {
      assert.doesNotThrow(() =>
        DragEvent.prepareEvent(buildEvent("dragstart", null)),
      );
    });

    for (const type of [
      "drag",
      "dragend",
      "dragenter",
      "dragleave",
      "dragover",
      "drop",
    ]) {
      it(`leaves a ${type} alone`, () => {
        // The browser protects the drag data outside dragstart, so a write is ignored, or throws in
        // Firefox.
        const dataTransfer = {
          setData: sinon.spy(() => {
            throw new Error("protected");
          }),
          types: [],
        };

        DragEvent.prepareEvent(buildEvent(type, dataTransfer));

        sinon.assert.notCalled(dataTransfer.setData);
      });
    }
  });
});
