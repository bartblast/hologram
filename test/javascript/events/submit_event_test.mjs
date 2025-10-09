"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  JSDOM,
} from "../support/helpers.mjs";

import SubmitEvent from "../../../assets/js/events/submit_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("SubmitEvent", () => {
  describe("buildOperationParam()", () => {
    it("handles text-based inputs", () => {
      const dom = new JSDOM(`
        <html>
          <body>
            <form id="my_form">
              <input name="name" value="John Doe">
              <input name="email" value="john.doe@example.com">
            </form>
          </body>
        </html>
      `);

      const event = {target: dom.window.document.getElementById("my_form")};
      const result = SubmitEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.bitstring("name"), Type.bitstring("John Doe")],
          [Type.bitstring("email"), Type.bitstring("john.doe@example.com")],
        ]),
      );
    });

    it("handles checkbox inputs with boolean values", () => {
      const dom = new JSDOM(`
        <html>
          <body>
            <form id="my_form">
              <input type="checkbox" name="subscribe" checked>
              <input type="checkbox" name="terms_of_service">
              <input name="name" value="John Doe">
            </form>
          </body>
        </html>
      `);

      const event = {target: dom.window.document.getElementById("my_form")};
      const result = SubmitEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.bitstring("subscribe"), Type.boolean(true)],
          [Type.bitstring("name"), Type.bitstring("John Doe")],
        ]),
      );
    });

    it("handles radio inputs with their selected values", () => {
      const dom = new JSDOM(`
        <html>
          <body>
            <form id="my_form">
              <input type="radio" name="gender" value="male" checked>
              <input type="radio" name="gender" value="female">
              <input name="name" value="John Doe">
            </form>
          </body>
        </html>
      `);

      const event = {target: dom.window.document.getElementById("my_form")};
      const result = SubmitEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.bitstring("gender"), Type.bitstring("male")],
          [Type.bitstring("name"), Type.bitstring("John Doe")],
        ]),
      );
    });

    it("handles single-select inputs with their selected values", () => {
      const dom = new JSDOM(`
        <html>
          <body>
            <form id="my_form">
              <select name="country">
                <option value="br">Brazil</option>
                <option value="pl" selected>Poland</option>
                <option value="us">United States</option>
              </select>
              <input name="city" value="Warsaw">
            </form>
          </body>
        </html>
      `);

      const event = {target: dom.window.document.getElementById("my_form")};
      const result = SubmitEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.bitstring("country"), Type.bitstring("pl")],
          [Type.bitstring("city"), Type.bitstring("Warsaw")],
        ]),
      );
    });
  });

  it("isEventIgnored()", () => {
    const dom = new JSDOM(`
      <html>
        <body>
          <form id="my_form">
            <input name="name" value="John Doe">
          </form>
        </body>
      </html>
    `);

    const event = {target: dom.window.document.getElementById("my_form")};
    assert.isFalse(SubmitEvent.isEventIgnored(event));
  });
});
