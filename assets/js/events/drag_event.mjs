"use strict";

import MouseEvent from "../events/mouse_event.mjs";
import Type from "../type.mjs";

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

export default class DragEvent {
  // Allow the browser's native default. A dragstart's default starts the drag and a drag over an
  // element that isn't a drop target refuses the drop, so the default is left to run; a binding
  // that needs to suppress it opts in with prevent_default.
  static isDefaultAllowed = true;

  // The type Hologram puts on a drag that would otherwise carry no data, since Firefox doesn't
  // start such a drag. It is Hologram's own, so the payload leaves it out.
  static PLACEHOLDER_TYPE = "application/x-hologram";

  // Deps: [:maps.merge/2]
  static buildOperationParam(event) {
    const mouseEventDetails = MouseEvent.buildOperationParam(event);

    const dragEventDetails = Type.map([
      [Type.atom("data_transfer"), $.#buildDataTransfer(event)],
    ]);

    // DragEvent inherits properties from MouseEvent
    // See: https://developer.mozilla.org/en-US/docs/Web/API/DragEvent#instance_properties
    return Erlang_Maps["merge/2"](mouseEventDetails, dragEventDetails);
  }

  static isEventIgnored(_event) {
    return false;
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
      [Type.atom("files"), Type.list()],
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
}

const $ = DragEvent;
