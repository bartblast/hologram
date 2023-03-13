"use strict";

import {
  assert,
  assertFrozen,
  cleanup,
} from "../../support/commons";
beforeEach(() => cleanup());

import BlurEvent from "../../../../assets/js/hologram/events/blur_event"
import Type from "../../../../assets/js/hologram/type";

describe("buildEventData()", () => {
  it("returns frozen empty boxed map", () => {
    const result = BlurEvent.buildEventData(new Event("blur"), "input")

    assert.deepStrictEqual(result, Type.map())
    assertFrozen(result)
  })
})