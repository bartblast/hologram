"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import BeforeInputEvent from "../../../assets/js/events/before_input_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("BeforeInputEvent", () => {
  afterEach(() => {
    document.body.innerHTML = "";
    window.getSelection()?.removeAllRanges();
  });

  it("buildOperationParam() handles text controls", () => {
    const target = {
      tagName: "TEXTAREA",
      value: "Hologram",
      selectionStart: 1,
      selectionEnd: 4,
      selectionDirection: "forward",
    };

    const event = {
      target,
      currentTarget: target,
      inputType: "insertText",
      data: "x",
      isComposing: true,
    };

    const result = BeforeInputEvent.buildOperationParam(event);

    assert.deepStrictEqual(
      result,
      Type.map([
        [Type.atom("input_type"), Type.bitstring("insertText")],
        [Type.atom("data"), Type.bitstring("x")],
        [Type.atom("is_composing"), Type.boolean(true)],
        [
          Type.atom("selection"),
          Type.map([
            [Type.atom("selection_start"), Type.integer(1)],
            [Type.atom("selection_end"), Type.integer(4)],
            [Type.atom("selection_direction"), Type.bitstring("forward")],
          ]),
        ],
        [Type.atom("selection_start"), Type.integer(1)],
        [Type.atom("selection_end"), Type.integer(4)],
        [Type.atom("selection_direction"), Type.bitstring("forward")],
      ]),
    );
  });

  it("buildOperationParam() handles contenteditable DOM selections", () => {
    document.body.innerHTML =
      '<div id="root" contenteditable="true">ab<span>cd</span></div>';

    const root = document.getElementById("root");
    const range = document.createRange();
    range.setStart(root.firstChild, 1);
    range.setEnd(root.childNodes[1].firstChild, 1);

    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);

    const result = BeforeInputEvent.buildOperationParam({
      target: root,
      currentTarget: root,
      inputType: "deleteContentBackward",
      data: null,
      isComposing: false,
    });

    assert.deepStrictEqual(
      result,
      Type.map([
        [Type.atom("input_type"), Type.bitstring("deleteContentBackward")],
        [Type.atom("data"), Type.nil()],
        [Type.atom("is_composing"), Type.boolean(false)],
        [
          Type.atom("selection"),
          Type.map([
            [Type.atom("anchor_path"), Type.list([Type.integer(0)])],
            [Type.atom("anchor_offset"), Type.integer(1)],
            [
              Type.atom("focus_path"),
              Type.list([Type.integer(1), Type.integer(0)]),
            ],
            [Type.atom("focus_offset"), Type.integer(1)],
            [Type.atom("direction"), Type.bitstring("forward")],
          ]),
        ],
        [Type.atom("selection_start"), Type.nil()],
        [Type.atom("selection_end"), Type.nil()],
        [Type.atom("selection_direction"), Type.nil()],
      ]),
    );
  });

  it("isEventIgnored()", () => {
    assert.isFalse(BeforeInputEvent.isEventIgnored({}));
  });
});
