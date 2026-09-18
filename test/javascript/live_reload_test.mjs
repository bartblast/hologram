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
    LiveReload.stalePageModules = new Set();
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

    it("marks the rebuilt pages stale when the page shown was not rebuilt", () => {
      sinon.stub(LiveReload, "reload");

      LiveReload.handleReload(["Elixir.MyApp.Page2"], currentPageModule);
      LiveReload.handleReload(["Elixir.MyApp.Page3"], currentPageModule);

      assert.deepStrictEqual(
        LiveReload.stalePageModules,
        new Set(["Elixir.MyApp.Page2", "Elixir.MyApp.Page3"]),
      );
    });
  });

  describe("isStale()", () => {
    it("a page no reload has rebuilt", () => {
      assert.isFalse(LiveReload.isStale(Type.atom("Elixir.MyApp.Page2")));
    });

    it("a page a reload has rebuilt", () => {
      sinon.stub(LiveReload, "reload");

      LiveReload.handleReload(
        ["Elixir.MyApp.Page2"],
        Type.atom("Elixir.MyApp.Page1"),
      );

      assert.isTrue(LiveReload.isStale(Type.atom("Elixir.MyApp.Page2")));
    });
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
