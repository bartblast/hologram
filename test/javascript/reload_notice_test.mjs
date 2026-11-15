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

    describe("when the person asks for a reload", () => {
      let record, reloading;

      beforeEach(() => {
        reloading = sinon.stub(Hologram, "reloadBrowserLocation");

        Hologram.dataLayer = {
          saved: () =>
            new Promise((resolve) => {
              record = resolve;
            }),
        };
      });

      afterEach(() => {
        Hologram.dataLayer = null;
      });

      // A reload would otherwise cut short a write still on its way into the store.
      it("reloads the page once what the person wrote is saved", async () => {
        ReloadNotice.update(true);

        buttons()[0].click();

        await clock.tickAsync(0);

        sinon.assert.notCalled(reloading);

        record();

        await clock.tickAsync(0);

        sinon.assert.calledOnce(reloading);
      });

      // The wait can be long enough to click again.
      it("takes one click while it waits", async () => {
        ReloadNotice.update(true);

        buttons()[0].click();
        buttons()[0].click();

        assert.isTrue(buttons()[0].disabled);

        record();

        await clock.tickAsync(0);

        sinon.assert.calledOnce(reloading);
      });

      // A reload the page's own beforeunload prompt talked the person out of.
      it("can be clicked again once the wait is over", async () => {
        ReloadNotice.update(true);

        buttons()[0].click();
        record();

        await clock.tickAsync(0);

        assert.isFalse(buttons()[0].disabled);
      });
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
