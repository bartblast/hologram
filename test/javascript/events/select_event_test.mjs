"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import SelectEvent from "../../../assets/js/events/select_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("SelectEvent", () => {
  const event = {
    target: {
      tagName: "INPUT",
      type: "text",
      selectionEnd: 15,
      selectionStart: 6,
      selectionDirection: "none",
      value: "Hologram 1 Hologram",
    },
  };

  it("buildOperationParam()", () => {
    const result = SelectEvent.buildOperationParam(event);

    assert.deepStrictEqual(
      result,
      Type.map([
        [Type.atom("value"), Type.bitstring("am 1 Holo")],
        [Type.atom("selection_start"), Type.integer(6)],
        [Type.atom("selection_end"), Type.integer(15)],
        [Type.atom("selection_direction"), Type.bitstring("none")],
      ]),
    );
  });

  it("buildOperationParam() handles non-text controls defensively", () => {
    const result = SelectEvent.buildOperationParam({
      target: {tagName: "INPUT", type: "color", value: "#123456"},
    });

    assert.deepStrictEqual(
      result,
      Type.map([
        [Type.atom("value"), Type.bitstring("")],
        [Type.atom("selection_start"), Type.nil()],
        [Type.atom("selection_end"), Type.nil()],
        [Type.atom("selection_direction"), Type.nil()],
      ]),
    );
  });

  it("isEventIgnored()", () => {
    assert.isFalse(SelectEvent.isEventIgnored(event));
  });
});
