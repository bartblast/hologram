"use strict";

import {assert, linkModules, unlinkModules} from "../support/helpers.mjs";

import ClickEvent from "../../../assets/js/events/click_event.mjs";
import Type from "../../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

it("buildOperationParam()", () => {
  const event = {};
  const result = ClickEvent.buildOperationParam(event);

  assert.deepStrictEqual(result, Type.map([]));
});

describe("isEventIgnored()", () => {
  it("no special keys are pressed, main button is pressed", () => {
    const event = {ctrlKey: false, metaKey: false, shiftKey: false, button: 0};
    assert.isFalse(ClickEvent.isEventIgnored(event));
  });

  it("no special keys are pressed, auxiliary button is pressed", () => {
    const event = {ctrlKey: false, metaKey: false, shiftKey: false, button: 1};
    assert.isTrue(ClickEvent.isEventIgnored(event));
  });

  it("ctrl key is pressed, main button is pressed", () => {
    const event = {ctrlKey: true, metaKey: false, shiftKey: false, button: 0};
    assert.isTrue(ClickEvent.isEventIgnored(event));
  });

  it("meta key is pressed, main button is pressed", () => {
    const event = {ctrlKey: false, metaKey: true, shiftKey: false, button: 0};
    assert.isTrue(ClickEvent.isEventIgnored(event));
  });

  it("shift key is pressed, main button is pressed", () => {
    const event = {ctrlKey: false, metaKey: false, shiftKey: true, button: 0};
    assert.isTrue(ClickEvent.isEventIgnored(event));
  });
});
