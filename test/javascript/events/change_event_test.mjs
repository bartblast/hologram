"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  JSDOM,
} from "../support/helpers.mjs";

import ChangeEvent from "../../../assets/js/events/change_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("ChangeEvent", () => {
  describe("buildOperationParam()", () => {
    it("handles checkbox inputs", () => {
      const target = {tagName: "INPUT", type: "checkbox", checked: true};

      const event = {
        target: target,
        currentTarget: target, // For individual field events, currentTarget == target
      };

      const result = ChangeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.atom("value"), Type.boolean(true)]]),
      );
    });

    it("handles radio inputs", () => {
      const target = {tagName: "INPUT", type: "radio", checked: false};

      const event = {
        target: target,
        currentTarget: target, // For individual field events, currentTarget = target
      };

      const result = ChangeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.atom("value"), Type.boolean(false)]]),
      );
    });

    it("handles single select elements", () => {
      const target = {tagName: "SELECT", value: "option_2"};

      const event = {
        target: target,
        currentTarget: target, // For individual field events, currentTarget = target
      };

      const result = ChangeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.atom("value"), Type.bitstring("option_2")]]),
      );
    });

    it("handles multiple select elements", () => {
      const selectedOptions = [{value: "option_1"}, {value: "option_3"}];

      const target = {
        tagName: "SELECT",
        multiple: true,
        selectedOptions: selectedOptions,
      };

      const event = {
        target: target,
        currentTarget: target, // For individual field events, currentTarget = target
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
      const target = {tagName: "TEXTAREA", value: "Some text content"};

      const event = {
        target: target,
        currentTarget: target, // For individual field events, currentTarget = target
      };

      const result = ChangeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.atom("value"), Type.bitstring("Some text content")]]),
      );
    });

    it("handles other input types as text", () => {
      const target = {
        tagName: "INPUT",
        type: "email",
        value: "test@example.com",
      };

      const event = {
        target: target,
        currentTarget: target, // For individual field events, currentTarget = target
      };

      const result = ChangeEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.atom("value"), Type.bitstring("test@example.com")]]),
      );
    });

    it("handles form-level change events", () => {
      const dom = new JSDOM(`
        <html>
          <body>
            <form id="my_form">
              <input name="username" value="john_doe">
              <input name="email" value="john@example.com">
            </form>
          </body>
        </html>
      `);

      const form = dom.window.document.getElementById("my_form");
      const input = form.querySelector('input[name="username"]');

      // For form-level events: target is the input, currentTarget is the form
      const event = {
        target: input,
        currentTarget: form,
      };

      const result = ChangeEvent.buildOperationParam(event);

      // Should delegate to SubmitEvent and collect all form data
      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.bitstring("username"), Type.bitstring("john_doe")],
          [Type.bitstring("email"), Type.bitstring("john@example.com")],
        ]),
      );
    });
  });

  it("isEventIgnored()", () => {
    const target = {value: "my_value"};

    const event = {
      target: target,
      currentTarget: target,
    };

    assert.isFalse(ChangeEvent.isEventIgnored(event));
  });
});
