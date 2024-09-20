"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import ChangeEvent from "../../../assets/js/events/change_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("ChangeEvent", () => {
  const event = {target: {value: "my_value"}};

  it("buildOperationParam()", () => {
    const result = ChangeEvent.buildOperationParam(event);

    assert.deepStrictEqual(
      result,
      Type.map([[Type.atom("value"), Type.bitstring("my_value")]]),
    );
  });

  it("isEventIgnored()", () => {
    assert.isFalse(ChangeEvent.isEventIgnored(event));
  });
});
