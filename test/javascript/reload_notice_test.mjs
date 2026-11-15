"use strict";

import {
  assert,
  defineRuntimeGlobals,
  JSDOM,
  sinon,
} from "./support/helpers.mjs";

import Hologram from "../../assets/js/hologram.mjs";
import ReloadNotice from "../../assets/js/reload_notice.mjs";

defineRuntimeGlobals();

describe("ReloadNotice", () => {
  let originalDocument;
  let window;

  const notice = () => document.getElementById("hologram-reload-notice");

  const buttons = () => notice().querySelectorAll("button");

  let clock;

  beforeEach(() => {
    clock = sinon.useFakeTimers();

    originalDocument = globalThis.document;
    ({window} = new JSDOM("<!DOCTYPE html><html><body></body></html>"));
    globalThis.document = window.document;
  });

  afterEach(() => {
    ReloadNotice.reset();
    sinon.restore();
    globalThis.document = originalDocument;
  });

  describe("update()", () => {
    it("shows the notice once the tab is stopped", () => {
      ReloadNotice.update(true);

      clock.tick(100);

      assert.equal(notice().parentNode, document.body);

      assert.include(
        notice().textContent,
        "This page was updated and needs a reload to keep your data in sync.",
      );
    });

    // A screen reader announces what changes in a status region, and passes over one whose text
    // arrives with it.
    it("writes the text a moment after the notice is up", () => {
      ReloadNotice.update(true);

      assert.notInclude(notice().textContent, "This page was updated");

      clock.tick(99);

      assert.notInclude(notice().textContent, "This page was updated");

      clock.tick(1);

      assert.include(notice().textContent, "This page was updated");
    });

    // A status is read out without taking the focus from what the person is doing.
    it("is a status", () => {
      ReloadNotice.update(true);

      assert.equal(notice().getAttribute("role"), "status");
    });

    it("shows nothing while the tab is served", () => {
      ReloadNotice.update(false);

      assert.isNull(notice());
    });

    it("shows one notice however many renders follow", () => {
      ReloadNotice.update(true);
      ReloadNotice.update(true);

      assert.equal(
        document.querySelectorAll("#hologram-reload-notice").length,
        1,
      );
    });

    // Something outside Hologram took it out of the page, and the next render puts it back.
    it("shows the notice again when something took it out of the page", () => {
      ReloadNotice.update(true);

      notice().remove();

      ReloadNotice.update(true);

      assert.isNotNull(notice());
    });

    it("reloads the page when the person asks for it", () => {
      const reloading = sinon.stub(Hologram, "reloadBrowserLocation");

      ReloadNotice.update(true);

      buttons()[0].click();

      sinon.assert.calledOnce(reloading);
    });

    // The framework never reloads a page on its own.
    it("leaves the page where it is until the person asks", () => {
      const reloading = sinon.stub(Hologram, "reloadBrowserLocation");

      ReloadNotice.update(true);

      sinon.assert.notCalled(reloading);
    });

    it("goes away when the person puts it away, and stays away", () => {
      ReloadNotice.update(true);

      buttons()[1].click();

      assert.isNull(notice());

      ReloadNotice.update(true);

      assert.isNull(notice());
    });

    // Neither submits a form the page happens to have around it.
    it("has buttons that submit nothing", () => {
      ReloadNotice.update(true);

      assert.deepStrictEqual(
        Array.from(buttons()).map((button) => button.type),
        ["button", "button"],
      );
    });

    it("names the dismiss button for a screen reader", () => {
      ReloadNotice.update(true);

      assert.equal(buttons()[1].getAttribute("aria-label"), "Dismiss");
    });
  });
});
