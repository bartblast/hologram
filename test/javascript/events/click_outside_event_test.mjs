"use strict";

import {assert, defineRuntimeGlobals} from "../support/helpers.mjs";

import ClickOutsideEvent from "../../../assets/js/events/click_outside_event.mjs";
import PointerEvent from "../../../assets/js/events/pointer_event.mjs";

defineRuntimeGlobals();

describe("ClickOutsideEvent", () => {
  it("buildEventParam()", () => {
    const event = {
      clientX: 10,
      clientY: 20,
      movementX: 5,
      movementY: 15,
      offsetX: 30,
      offsetY: 40,
      pageX: 1,
      pageY: 2,
      pointerType: "mouse",
      screenX: 100,
      screenY: 200,
    };

    assert.deepStrictEqual(
      ClickOutsideEvent.buildEventParam(event),
      PointerEvent.buildEventParam(event),
    );
  });

  it("isEventIgnored()", () => {
    assert.isFalse(ClickOutsideEvent.isEventIgnored({}));
  });
});
