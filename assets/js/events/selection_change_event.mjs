"use strict";

import DomSelection from "../dom_selection.mjs";
import Type from "../type.mjs";

export default class SelectionChangeEvent {
  static isDefaultAllowed = true;

  static buildOperationParam(event) {
    const selection = DomSelection.buildDomSelection(event.currentTarget);

    return Type.map([
      [
        Type.atom("value"),
        Type.bitstring(selection === null ? "" : selection.value),
      ],
      [Type.atom("selection"), $.boxDomSelection(selection)],
    ]);
  }

  static boxDomSelection(selection) {
    if (selection === null) {
      return Type.nil();
    }

    return Type.map([
      [Type.atom("anchor_path"), $.boxPath(selection.anchorPath)],
      [Type.atom("anchor_offset"), Type.integer(selection.anchorOffset)],
      [Type.atom("focus_path"), $.boxPath(selection.focusPath)],
      [Type.atom("focus_offset"), Type.integer(selection.focusOffset)],
      [Type.atom("direction"), Type.bitstring(selection.direction)],
    ]);
  }

  static boxPath(path) {
    return Type.list(path.map((index) => Type.integer(index)));
  }

  static isEventIgnored(event) {
    return DomSelection.buildDomSelection(event.currentTarget) === null;
  }
}

const $ = SelectionChangeEvent;
