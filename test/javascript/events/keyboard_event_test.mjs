"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import KeyboardEvent from "../../../assets/js/events/keyboard_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("KeyboardEvent", () => {
  it("buildOperationParam()", () => {
    const event = {
      altKey: false,
      code: "KeyK",
      ctrlKey: true,
      key: "k",
      metaKey: false,
      repeat: true,
      shiftKey: true,
    };

    const result = KeyboardEvent.buildOperationParam(event);

    assert.deepStrictEqual(
      result,
      Type.map([
        [Type.atom("alt_key"), Type.boolean(false)],
        [Type.atom("code"), Type.bitstring("KeyK")],
        [Type.atom("ctrl_key"), Type.boolean(true)],
        [Type.atom("key"), Type.bitstring("k")],
        [Type.atom("meta_key"), Type.boolean(false)],
        [Type.atom("repeat"), Type.boolean(true)],
        [Type.atom("shift_key"), Type.boolean(true)],
      ]),
    );
  });

  it("isEventIgnored()", () => {
    assert.isFalse(KeyboardEvent.isEventIgnored({}));
  });
});
