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

  it("buildOperationParam()", () => {
    const result = SubmitEvent.buildOperationParam(event);

    assert.deepStrictEqual(
      result,
      Type.map([
        [Type.bitstring("name"), Type.bitstring("John Doe")],
        [Type.bitstring("email"), Type.bitstring("john.doe@example.com")],
      ]),
    );
  });

  it("isEventIgnored()", () => {
    assert.isFalse(SubmitEvent.isEventIgnored(event));
  });
});
