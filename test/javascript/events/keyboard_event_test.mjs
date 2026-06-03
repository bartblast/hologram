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

  describe("matchesKeyFilter()", () => {
    it("matches a named key against the lowercased event.key", () => {
      const filter = Type.list([Type.bitstring("enter")]);

      assert.isTrue(KeyboardEvent.matchesKeyFilter(filter, {key: "Enter"}));
      assert.isFalse(KeyboardEvent.matchesKeyFilter(filter, {key: "Escape"}));
    });

    it("matches the key case-insensitively", () => {
      const filter = Type.list([Type.bitstring("k")]);

      // Shift or Caps Lock makes event.key uppercase "K".
      assert.isTrue(KeyboardEvent.matchesKeyFilter(filter, {key: "K"}));
    });

    it("matches an arrow key against its PascalCase event.key", () => {
      const filter = Type.list([Type.bitstring("arrowup")]);

      assert.isTrue(KeyboardEvent.matchesKeyFilter(filter, {key: "ArrowUp"}));
    });

    it("requires the filtered modifier to be held", () => {
      const filter = Type.list([Type.bitstring("ctrl"), Type.bitstring("k")]);

      assert.isTrue(
        KeyboardEvent.matchesKeyFilter(filter, {key: "k", ctrlKey: true}),
      );

      assert.isFalse(
        KeyboardEvent.matchesKeyFilter(filter, {key: "k", ctrlKey: false}),
      );
    });

    it("requires every filtered modifier to be held", () => {
      const filter = Type.list([
        Type.bitstring("ctrl"),
        Type.bitstring("shift"),
        Type.bitstring("k"),
      ]);

      assert.isTrue(
        KeyboardEvent.matchesKeyFilter(filter, {
          key: "k",
          ctrlKey: true,
          shiftKey: true,
        }),
      );

      // ctrl is held but shift is not - one missing modifier fails the match.
      assert.isFalse(
        KeyboardEvent.matchesKeyFilter(filter, {
          key: "k",
          ctrlKey: true,
          shiftKey: false,
        }),
      );
    });

    it("matches when extra unfiltered modifiers are also held (superset)", () => {
      const filter = Type.list([Type.bitstring("ctrl"), Type.bitstring("k")]);

      assert.isTrue(
        KeyboardEvent.matchesKeyFilter(filter, {
          key: "k",
          ctrlKey: true,
          shiftKey: true,
        }),
      );
    });

    it("matches a no-modifier filter regardless of held modifiers", () => {
      const filter = Type.list([Type.bitstring("enter")]);

      assert.isTrue(
        KeyboardEvent.matchesKeyFilter(filter, {
          key: "Enter",
          ctrlKey: true,
          shiftKey: true,
        }),
      );
    });
  });
});
