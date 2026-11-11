"use strict";

import DroppedFileRegistry from "../dropped_file_registry.mjs";
import MouseEvent from "../events/mouse_event.mjs";
import Type from "../type.mjs";
import Utils from "../utils.mjs";

// What each effectAllowed value allows, by effect. A drag whose source set nothing reports
// "uninitialized", which allows every effect, as does a value no browser reports.
const EFFECTS_ALLOWED = {
  all: ["copy", "link", "move"],
  copy: ["copy"],
  copyLink: ["copy", "link"],
  copyMove: ["copy", "move"],
  link: ["link"],
  linkMove: ["link", "move"],
  move: ["move"],
  none: [],
  uninitialized: ["copy", "link", "move"],
};

// What a DragEvent built by a script with no DataTransfer reads as: a drag with nothing on it.
const EMPTY_DATA_TRANSFER = {
  dropEffect: "none",
  effectAllowed: "uninitialized",
  items: [],
  types: [],
};

// The files of each drop event, built once: an event reaches every $drop binding on its path, and
// each binding has to see the same paths, with each file registered once.
const filesByDropEvent = new WeakMap();

export default class DragEvent {
  // Allow the browser's native default. A dragstart's default starts the drag and a drag over an
  // element that isn't a drop target refuses the drop, so the default is left to run; a binding
  // that needs to suppress it opts in with prevent_default.
  static isDefaultAllowed = true;

  // The type Hologram puts on a drag that would otherwise carry no data, since Firefox doesn't
  // start such a drag. It is Hologram's own, so the payload leaves it out.
  static PLACEHOLDER_TYPE = "application/x-hologram";

  // Deps: [:maps.merge/2]
  static buildEventParam(event) {
    const mouseEventDetails = MouseEvent.buildEventParam(event);

    const dragEventDetails = Type.map([
      [Type.atom("data_transfer"), $.#buildDataTransfer(event)],
    ]);

    // DragEvent inherits properties from MouseEvent
    // See: https://developer.mozilla.org/en-US/docs/Web/API/DragEvent#instance_properties
    return Erlang_Maps["merge/2"](mouseEventDetails, dragEventDetails);
  }

  // Each time a drag crosses between an element and one of its children, the element gets a
  // dragenter and a dragleave, its own or bubbled up from the child. Both are ignored when the
  // element contains the relatedTarget, which is the node the drag came from on dragenter and the
  // one it goes to on dragleave. The window and the document ignore every crossing inside the page.
  // A drag from outside the page, or a browser that leaves relatedTarget unset (Safari before the
  // WebKit bug 66547 fix), has a null relatedTarget and fires.
  static isEventIgnored(event) {
    if (event.type !== "dragenter" && event.type !== "dragleave") {
      return false;
    }

    const currentTarget = event.currentTarget;
    const relatedTarget = event.relatedTarget ?? null;

    if (relatedTarget === null) {
      return false;
    }

    if (
      currentTarget === globalThis.window ||
      currentTarget === globalThis.document
    ) {
      return true;
    }

    return currentTarget.contains(relatedTarget);
  }

  // Firefox starts a drag only when a dragstart listener puts data on it (Mozilla bug 725156), so a
  // dragstart that carries none gets the placeholder. The browser lets a page write the drag data
  // only while dragstart runs. A write during any other drag event is ignored, and Firefox throws.
  static prepareEvent(event) {
    if (
      event.type === "dragstart" &&
      event.dataTransfer &&
      event.dataTransfer.types.length === 0
    ) {
      event.dataTransfer.setData($.PLACEHOLDER_TYPE, "hologram");
    }
  }

  // The browser lets a page read the drag data only while dragstart and drop run; any other drag
  // event shows only the types and items. "Files" names the dropped files rather than data a page
  // can get.
  static #buildData(event, dataTransfer, types) {
    if (event.type !== "dragstart" && event.type !== "drop") {
      return Type.map();
    }

    return Type.map(
      types
        .filter((type) => type !== "Files")
        .map((type) => [
          Type.bitstring(type),
          Type.bitstring(dataTransfer.getData(type)),
        ]),
    );
  }

  static #buildDataTransfer(event) {
    const dataTransfer = event.dataTransfer ?? EMPTY_DATA_TRANSFER;

    const types = Array.from(dataTransfer.types).filter(
      (type) => type !== $.PLACEHOLDER_TYPE,
    );

    const items = Array.from(dataTransfer.items).filter(
      (item) => item.type !== $.PLACEHOLDER_TYPE,
    );

    return Type.map([
      [Type.atom("data"), $.#buildData(event, dataTransfer, types)],
      [Type.atom("drop_effect"), Type.atom(dataTransfer.dropEffect)],
      [
        Type.atom("effects_allowed"),
        $.#buildEffectsAllowed(dataTransfer.effectAllowed),
      ],
      [Type.atom("files"), $.#buildFiles(event, items)],
      [
        Type.atom("items"),
        Type.list(
          items.map((item) =>
            Type.map([
              [Type.atom("kind"), Type.atom(item.kind)],
              [Type.atom("type"), Type.bitstring(item.type)],
            ]),
          ),
        ),
      ],
      [
        Type.atom("types"),
        Type.list(types.map((type) => Type.bitstring(type))),
      ],
    ]);
  }

  static #buildEffectsAllowed(effectAllowed) {
    const allowed = Object.hasOwn(EFFECTS_ALLOWED, effectAllowed)
      ? EFFECTS_ALLOWED[effectAllowed]
      : EFFECTS_ALLOWED.uninitialized;

    return Type.map(
      ["copy", "link", "move"].map((effect) => [
        Type.atom(effect),
        Type.boolean(allowed.includes(effect)),
      ]),
    );
  }

  // Each dropped file goes in the registry under a folder of its own, named by a new id, so two
  // files of one drop with the same name stay apart, and a path kept from before a reload never
  // names a file a later drop brought. A folder is kept as its entry, since its File reads as an
  // empty file. A DataTransfer built by a script has no entries, so its items are read as plain
  // files.
  static #buildFiles(event, items) {
    if (event.type !== "drop") {
      return Type.list();
    }

    if (filesByDropEvent.has(event)) {
      return filesByDropEvent.get(event);
    }

    const files = items
      .filter((item) => item.kind === "file")
      .map((item) => {
        const entry = item.webkitGetAsEntry?.() ?? null;
        const value = entry?.isDirectory ? entry : item.getAsFile();

        if (value === null) {
          return null;
        }

        const path = `/$hologram/drops/${Utils.uuidv7()}/${value.name}`;

        DroppedFileRegistry.put(path, value);

        return Type.struct("Hologram.File", [
          [Type.atom("path"), Type.bitstring(path)],
        ]);
      })
      .filter((file) => file !== null);

    const boxedFiles = Type.list(files);

    filesByDropEvent.set(event, boxedFiles);

    return boxedFiles;
  }
}

const $ = DragEvent;
