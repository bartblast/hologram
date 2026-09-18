"use strict";

import {assert, defineRuntimeGlobals, sinon} from "./support/helpers.mjs";

import ErrorOverlay from "../../assets/js/error_overlay.mjs";
import LiveReload from "../../assets/js/live_reload.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

const OVERLAY_ID = "hologram-live-reload-error-overlay";

describe("LiveReload", () => {
  const originalDocument = globalThis.document;

  // Undone here rather than at the end of each test, since a failed assertion
  // would otherwise leave the document replaced for every suite that follows.
  afterEach(() => {
    globalThis.document = originalDocument;
    globalThis.Hologram.config.liveReload = false;
    LiveReload.pageBundleDigests = new Map();
    sinon.restore();
  });

  describe("handleReload()", () => {
    const currentPageModule = Type.atom("Elixir.MyApp.Page1");

    it("reloads when every tab must", () => {
      const reloadStub = sinon.stub(LiveReload, "reload");

      LiveReload.handleReload("all", currentPageModule);

      sinon.assert.calledOnce(reloadStub);
    });

    it("reloads when the page shown is among the rebuilt ones", () => {
      const reloadStub = sinon.stub(LiveReload, "reload");

      LiveReload.handleReload(
        ["Elixir.MyApp.Page2", "Elixir.MyApp.Page1"],
        currentPageModule,
      );

      sinon.assert.calledOnce(reloadStub);
    });

    it("does not reload when the page shown was not rebuilt", () => {
      const reloadStub = sinon.stub(LiveReload, "reload");

      LiveReload.handleReload(
        ["Elixir.MyApp.Page2", "Elixir.MyApp.Page3"],
        currentPageModule,
      );

      sinon.assert.notCalled(reloadStub);
    });
  });

  describe("holdsOldPageBundle()", () => {
    const pageModule = Type.atom("Elixir.MyApp.Page1");

    beforeEach(() => {
      globalThis.Hologram.config.liveReload = true;
    });

    it("a page this tab never loaded", () => {
      assert.isFalse(LiveReload.holdsOldPageBundle(pageModule, "digest-1"));
    });

    it("a page loaded under the digest the server serves", () => {
      LiveReload.recordPageBundle(pageModule, "digest-1");

      assert.isFalse(LiveReload.holdsOldPageBundle(pageModule, "digest-1"));
    });

    it("a page loaded under another digest", () => {
      LiveReload.recordPageBundle(pageModule, "digest-1");

      assert.isTrue(LiveReload.holdsOldPageBundle(pageModule, "digest-2"));
    });

    it("a page loaded under another digest, where live reload does not run", () => {
      globalThis.Hologram.config.liveReload = false;
      LiveReload.recordPageBundle(pageModule, "digest-1");

      assert.isFalse(LiveReload.holdsOldPageBundle(pageModule, "digest-2"));
    });
  });

  it("recordPageBundle()", () => {
    LiveReload.recordPageBundle(Type.atom("Elixir.MyApp.Page1"), "digest-1");
    LiveReload.recordPageBundle(Type.atom("Elixir.MyApp.Page1"), "digest-2");

    assert.deepStrictEqual(
      LiveReload.pageBundleDigests,
      new Map([["Elixir.MyApp.Page1", "digest-2"]]),
    );
  });

  it("reload()", () => {
    const reloadSpy = sinon.spy();

    globalThis.document = {location: {reload: reloadSpy}};

    LiveReload.reload();

    sinon.assert.calledOnce(reloadSpy);
  });

  it("showErrorOverlay()", () => {
    const showStub = sinon.stub(ErrorOverlay, "show");

    const lines = [
      [{text: "** (CompileError) cannot compile module MyApp", tone: "banner"}],
      [
        {text: "  3 │ ", tone: "chrome"},
        {text: "    foo()", tone: "body"},
      ],
    ];

    LiveReload.showErrorOverlay(lines);

    sinon.assert.calledOnceWithExactly(showStub, {
      content: lines,
      heading: "Compilation Error",
      id: OVERLAY_ID,
    });
  });
});
