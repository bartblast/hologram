"use strict";

import DomSelection from "../dom_selection.mjs";
import Type from "../type.mjs";

export default class BeforeInputEvent {
  static isDefaultAllowed = false;

  static buildOperationParam(event) {
    const target = event.target;
    const root = event.currentTarget || target;
    const textSelection = DomSelection.buildTextControlSelection(target);
    const domSelection =
      textSelection === null ? DomSelection.buildDomSelection(root) : null;

    return Type.map([
      [Type.atom("input_type"), Type.bitstring(event.inputType || "")],
      [Type.atom("data"), $.boxNullableBitstring(event.data)],
      [Type.atom("is_composing"), Type.boolean(event.isComposing === true)],
      [Type.atom("selection"), $.boxSelection(textSelection, domSelection)],
      [
        Type.atom("selection_start"),
        textSelection === null
          ? Type.nil()
          : Type.integer(textSelection.selectionStart),
      ],
      [
        Type.atom("selection_end"),
        textSelection === null
          ? Type.nil()
          : Type.integer(textSelection.selectionEnd),
      ],
      [
        Type.atom("selection_direction"),
        textSelection === null
          ? Type.nil()
          : Type.bitstring(textSelection.selectionDirection),
      ],
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

  static boxNullableBitstring(value) {
    return value === null || typeof value === "undefined"
      ? Type.nil()
      : Type.bitstring(value);
  }

  static boxPath(path) {
    return Type.list(path.map((index) => Type.integer(index)));
  }

  static boxSelection(textSelection, domSelection) {
    if (textSelection !== null) {
      return Type.map([
        [
          Type.atom("selection_start"),
          Type.integer(textSelection.selectionStart),
        ],
        [Type.atom("selection_end"), Type.integer(textSelection.selectionEnd)],
        [
          Type.atom("selection_direction"),
          Type.bitstring(textSelection.selectionDirection),
        ],
      ]);
    }

    return $.boxDomSelection(domSelection);
  }

  static isEventIgnored(_event) {
    return false;
  }
}

const $ = BeforeInputEvent;
