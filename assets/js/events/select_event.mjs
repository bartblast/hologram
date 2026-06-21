"use strict";

import DomSelection from "../dom_selection.mjs";
import Type from "../type.mjs";

export default class SelectEvent {
  static isDefaultAllowed = false;

  static buildOperationParam(event) {
    const selection = DomSelection.buildTextControlSelection(event.target);

    const value =
      selection === null
        ? ""
        : event.target.value.substring(
            selection.selectionStart,
            selection.selectionEnd,
          );

    return Type.map([
      [Type.atom("value"), Type.bitstring(value)],
      [
        Type.atom("selection_start"),
        selection === null
          ? Type.nil()
          : Type.integer(selection.selectionStart),
      ],
      [
        Type.atom("selection_end"),
        selection === null ? Type.nil() : Type.integer(selection.selectionEnd),
      ],
      [
        Type.atom("selection_direction"),
        selection === null
          ? Type.nil()
          : Type.bitstring(selection.selectionDirection),
      ],
    ]);
  }

  static isEventIgnored(_event) {
    return false;
  }
}
