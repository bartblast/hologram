"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import SelectionChangeEvent from "../../../assets/js/events/selection_change_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("SelectionChangeEvent", () => {
  afterEach(() => {
    document.body.innerHTML = "";
    window.getSelection()?.removeAllRanges();
  });

  it("buildOperationParam()", () => {
    document.body.innerHTML =
      '<div id="root" contenteditable="true">ab<span>cd</span></div>';

    const root = document.getElementById("root");
    const range = document.createRange();
    range.setStart(root.firstChild, 1);
    range.setEnd(root.childNodes[1].firstChild, 1);

    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);

    const result = SelectionChangeEvent.buildOperationParam({
      currentTarget: root,
    });

    assert.deepStrictEqual(
      result,
      Type.map([
        [Type.atom("value"), Type.bitstring("bc")],
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
      ]),
    );
  });

  it("isEventIgnored() returns true when selection is outside the root", () => {
    document.body.innerHTML =
      '<div id="root" contenteditable="true">ab</div><p id="outside">cd</p>';

    const root = document.getElementById("root");
    const outside = document.getElementById("outside");
    const range = document.createRange();
    range.selectNodeContents(outside);

    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);

    assert.isTrue(SelectionChangeEvent.isEventIgnored({currentTarget: root}));
  });

  it("isEventIgnored() returns false when selection is inside the root", () => {
    document.body.innerHTML = '<div id="root" contenteditable="true">ab</div>';

    const root = document.getElementById("root");
    const range = document.createRange();
    range.selectNodeContents(root.firstChild);

    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);

    assert.isFalse(SelectionChangeEvent.isEventIgnored({currentTarget: root}));
  });
});
