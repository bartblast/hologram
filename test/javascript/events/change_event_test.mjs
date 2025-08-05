"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import ChangeEvent from "../../../assets/js/events/change_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("ChangeEvent", () => {
  describe("buildOperationParam()", () => {
    it("handles text inputs", () => {
      const event = {target: {type: "text", value: "my_value"}};
      const result = ChangeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.atom("value"), Type.bitstring("my_value")]]),
      );
    });

    it("handles checkbox inputs", () => {
      const event = {target: {type: "checkbox", checked: true}};
      const result = ChangeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.atom("value"), Type.boolean(true)]]),
      );
    });

    it("handles radio inputs", () => {
      const event = {target: {type: "radio", checked: false}};
      const result = ChangeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.atom("value"), Type.boolean(false)]]),
      );
    });

    it("handles other input types as text", () => {
      const event = {target: {type: "email", value: "test@example.com"}};
      const result = ChangeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.atom("value"), Type.bitstring("test@example.com")]]),
      );
    });
  });

  it("isEventIgnored()", () => {
    const event = {target: {value: "my_value"}};
    assert.isFalse(ChangeEvent.isEventIgnored(event));
  });
});
