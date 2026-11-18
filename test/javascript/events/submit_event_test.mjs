"use strict";

import {assert, defineRuntimeGlobals, JSDOM} from "../support/helpers.mjs";

import SubmitEvent from "../../../assets/js/events/submit_event.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

// A formdata listener runs inside the FormData constructor, once the form's entries are in, and can
// change them or the form. A form-associated custom element can also add entries under any name.
// jsdom supports neither, so a FormData subclass runs the listener here.
function buildWithFormDataListener(formContent, listener) {
  const OriginalFormData = globalThis.FormData;

  globalThis.FormData = class extends OriginalFormData {
    constructor(form) {
      super(form);
      listener(this, form);
    }
  };

  try {
    const dom = new JSDOM(`
      <html>
        <body>
          <form id="my_form">${formContent}</form>
        </body>
      </html>
    `);

    const event = {target: dom.window.document.getElementById("my_form")};

    return SubmitEvent.buildOperationParam(event);
  } finally {
    globalThis.FormData = OriginalFormData;
  }
}

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

    it("handles checkboxes that share a name with another input as values", () => {
      const dom = new JSDOM(`
        <html>
          <body>
            <form id="my_form">
              <input type="hidden" name="subscribe" value="false">
              <input type="checkbox" name="subscribe" value="true" checked>
              <input type="checkbox" name="topics" value="news" checked>
              <input type="checkbox" name="topics" value="offers">
            </form>
          </body>
        </html>
      `);

      const event = {target: dom.window.document.getElementById("my_form")};
      const result = SubmitEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.bitstring("subscribe"), Type.bitstring("true")],
          [Type.bitstring("topics"), Type.bitstring("news")],
        ]),
      );
    });

    it("handles a checked checkbox in a group as a value", () => {
      const dom = new JSDOM(`
        <html>
          <body>
            <form id="my_form">
              <input type="checkbox" name="topics" value="news">
              <input type="checkbox" name="topics" value="offers" checked>
            </form>
          </body>
        </html>
      `);

      const event = {target: dom.window.document.getElementById("my_form")};
      const result = SubmitEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.bitstring("topics"), Type.bitstring("offers")]]),
      );
    });

    it("handles a lone radio input with the checkbox default value as a value", () => {
      const dom = new JSDOM(`
        <html>
          <body>
            <form id="my_form">
              <input type="radio" name="agree" value="on" checked>
            </form>
          </body>
        </html>
      `);

      const event = {target: dom.window.document.getElementById("my_form")};
      const result = SubmitEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.bitstring("agree"), Type.bitstring("on")]]),
      );
    });

    it("handles checkboxes with a lone surrogate or a leading BOM in their name or value", () => {
      const dom = new JSDOM(`
        <html>
          <body>
            <form id="my_form">
              <input type="checkbox" id="named" checked>
              <input type="checkbox" id="valued" name="valued" checked>
              <input type="checkbox" id="bom_named" checked>
              <input type="checkbox" id="bom_valued" name="bom_valued" checked>
            </form>
          </body>
        </html>
      `);

      const document = dom.window.document;
      document.getElementById("named").setAttribute("name", "named\uD800");
      document.getElementById("valued").setAttribute("value", "x\uD800");
      document
        .getElementById("bom_named")
        .setAttribute("name", "\uFEFFbom_named");
      document.getElementById("bom_valued").setAttribute("value", "\uFEFFx");

      const event = {target: document.getElementById("my_form")};
      const result = SubmitEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.bitstring("named�"), Type.boolean(true)],
          [Type.bitstring("valued"), Type.boolean(true)],
          [Type.bitstring("\uFEFFbom_named"), Type.boolean(true)],
          [Type.bitstring("bom_valued"), Type.boolean(true)],
        ]),
      );
    });

    it("handles checkboxes named after a form controls collection member", () => {
      const dom = new JSDOM(`
        <html>
          <body>
            <form id="my_form">
              <input type="checkbox" name="length" checked>
            </form>
          </body>
        </html>
      `);

      const event = {target: dom.window.document.getElementById("my_form")};
      const result = SubmitEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.bitstring("length"), Type.boolean(true)]]),
      );
    });

    it("handles a checkbox that shares its name with a dirname as a value", () => {
      const dom = new JSDOM(`
        <html>
          <body>
            <form id="my_form">
              <input name="comment" value="Hello" dirname="flag">
              <input type="checkbox" name="flag" checked>
            </form>
          </body>
        </html>
      `);

      const event = {target: dom.window.document.getElementById("my_form")};
      const result = SubmitEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.bitstring("comment"), Type.bitstring("Hello")],
          [Type.bitstring("flag"), Type.bitstring("on")],
        ]),
      );
    });

    it("handles a checked checkbox whose name a dirname that adds no entry uses", () => {
      const dom = new JSDOM(`
        <html>
          <body>
            <form id="my_form">
              <input name="comment" value="Hello" dirname="flag" disabled>
              <input type="checkbox" name="flag" checked>
            </form>
          </body>
        </html>
      `);

      const event = {target: dom.window.document.getElementById("my_form")};
      const result = SubmitEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([[Type.bitstring("flag"), Type.boolean(true)]]),
      );
    });

    describe("entries added under a checkbox's name by something other than the checkbox", () => {
      it("keeps the values when the checkbox is checked", () => {
        const result = buildWithFormDataListener(
          `<input type="checkbox" name="flag" checked>`,
          (formData) => formData.append("flag", "custom"),
        );

        assert.deepStrictEqual(
          result,
          Type.map([[Type.bitstring("flag"), Type.bitstring("custom")]]),
        );
      });

      it("keeps the value set in place of the checkbox's", () => {
        const result = buildWithFormDataListener(
          `<input type="checkbox" name="flag" checked>`,
          (formData) => formData.set("flag", "custom"),
        );

        assert.deepStrictEqual(
          result,
          Type.map([[Type.bitstring("flag"), Type.bitstring("custom")]]),
        );
      });

      it("keeps the value when the checkbox is unchecked", () => {
        const result = buildWithFormDataListener(
          `<input type="checkbox" name="flag">`,
          (formData) => formData.append("flag", "on"),
        );

        assert.deepStrictEqual(
          result,
          Type.map([[Type.bitstring("flag"), Type.bitstring("on")]]),
        );
      });

      it("keeps the value when the checkbox is disabled", () => {
        const result = buildWithFormDataListener(
          `<input type="checkbox" name="flag" checked disabled>`,
          (formData) => formData.append("flag", "on"),
        );

        assert.deepStrictEqual(
          result,
          Type.map([[Type.bitstring("flag"), Type.bitstring("on")]]),
        );
      });

      it("keeps the value when the checkbox is in a disabled fieldset", () => {
        const result = buildWithFormDataListener(
          `<fieldset disabled><input type="checkbox" name="flag" checked></fieldset>`,
          (formData) => formData.append("flag", "on"),
        );

        assert.deepStrictEqual(
          result,
          Type.map([[Type.bitstring("flag"), Type.bitstring("on")]]),
        );
      });

      it("keeps the value when the checkbox has an empty name", () => {
        const result = buildWithFormDataListener(
          `<input type="checkbox" name="" checked>`,
          (formData) => formData.append("", "on"),
        );

        assert.deepStrictEqual(
          result,
          Type.map([[Type.bitstring(""), Type.bitstring("on")]]),
        );
      });

      it("keeps the value when the checkbox is in a datalist", () => {
        const result = buildWithFormDataListener(
          `<datalist><input type="checkbox" name="flag" checked></datalist>`,
          (formData) => formData.append("flag", "on"),
        );

        assert.deepStrictEqual(
          result,
          Type.map([[Type.bitstring("flag"), Type.bitstring("on")]]),
        );
      });
    });

    it("handles a checkbox a formdata listener unchecks as checked", () => {
      const result = buildWithFormDataListener(
        `<input type="checkbox" name="flag" checked>`,
        (_formData, form) => {
          form.querySelector("input").checked = false;
        },
      );

      assert.deepStrictEqual(
        result,
        Type.map([[Type.bitstring("flag"), Type.boolean(true)]]),
      );
    });

    it("handles text inputs with a dirname", () => {
      const dom = new JSDOM(`
        <html>
          <body>
            <form id="my_form">
              <input name="comment" value="Hello" dirname="comment_dir">
              <input type="checkbox" name="notify" checked>
            </form>
          </body>
        </html>
      `);

      const event = {target: dom.window.document.getElementById("my_form")};
      const result = SubmitEvent.buildOperationParam(event);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.bitstring("comment"), Type.bitstring("Hello")],
          [Type.bitstring("comment_dir"), Type.bitstring("ltr")],
          [Type.bitstring("notify"), Type.boolean(true)],
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
