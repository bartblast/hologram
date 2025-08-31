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
    it("handles checkbox inputs", () => {
      const event = {
        target: {tagName: "INPUT", type: "checkbox", checked: true},
      };

      const result = ChangeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.atom("value"), Type.boolean(true)]]),
      );
    });

    it("handles radio inputs", () => {
      const event = {target: {tagName: "INPUT", type: "radio", checked: false}};
      const result = ChangeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.atom("value"), Type.boolean(false)]]),
      );
    });

    it("handles single select elements", () => {
      const event = {target: {tagName: "SELECT", value: "option_2"}};
      const result = ChangeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.atom("value"), Type.bitstring("option_2")]]),
      );
    });

    it("handles multiple select elements", () => {
      const selectedOptions = [{value: "option_1"}, {value: "option_3"}];

      const event = {
        target: {
          tagName: "SELECT",
          multiple: true,
          selectedOptions: selectedOptions,
        },
      };

      const result = ChangeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([
          [
            Type.atom("value"),
            Type.list([Type.bitstring("option_1"), Type.bitstring("option_3")]),
          ],
        ]),
      );
    });

    it("handles textarea elements", () => {
      const event = {target: {tagName: "TEXTAREA", value: "Some text content"}};
      const result = ChangeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.atom("value"), Type.bitstring("Some text content")]]),
      );
    });

    it("handles other input types as text", () => {
      const event = {
        target: {tagName: "INPUT", type: "email", value: "test@example.com"},
      };

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
