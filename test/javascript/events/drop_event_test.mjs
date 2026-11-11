"use strict";

import {assert, defineRuntimeGlobals, sinon} from "../support/helpers.mjs";

import DragEvent from "../../../assets/js/events/drag_event.mjs";
import DropEvent from "../../../assets/js/events/drop_event.mjs";

defineRuntimeGlobals();

describe("DropEvent", () => {
  it("isDefaultAllowed", () => {
    assert.isFalse(DropEvent.isDefaultAllowed);
  });

  it("buildEventParam()", () => {
    const dragEventBuildEventParamStub = sinon
      .stub(DragEvent, "buildEventParam")
      .callsFake(() => "dummy_param");

    const result = DropEvent.buildEventParam("dummy_event");

    assert.equal(result, "dummy_param");

    sinon.assert.calledOnceWithExactly(
      dragEventBuildEventParamStub,
      "dummy_event",
    );

    DragEvent.buildEventParam.restore();
  });

  it("isEventIgnored()", () => {
    const dragEventIsEventIgnoredStub = sinon
      .stub(DragEvent, "isEventIgnored")
      .callsFake(() => null);

    DropEvent.isEventIgnored("dummy_event");

    sinon.assert.calledOnceWithExactly(
      dragEventIsEventIgnoredStub,
      "dummy_event",
    );

    DragEvent.isEventIgnored.restore();
  });
});
