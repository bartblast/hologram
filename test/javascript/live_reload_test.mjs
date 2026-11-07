"use strict";

import {
  assert,
  defineRuntimeGlobals,
  JSDOM,
  sinon,
} from "./support/helpers.mjs";

import AssetPathRegistry from "../../assets/js/asset_path_registry.mjs";
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

  describe("heldPageDigest()", () => {
    it("no page", () => {
      assert.isNull(LiveReload.heldPageDigest(null));
    });

    it("a page this tab never loaded", () => {
      assert.isNull(LiveReload.heldPageDigest(Type.atom("Elixir.MyApp.Page1")));
    });

    it("a page this tab loaded", () => {
      const pageModule = Type.atom("Elixir.MyApp.Page1");
      LiveReload.recordPageBundle(pageModule, "digest-1");

      assert.equal(LiveReload.heldPageDigest(pageModule), "digest-1");
    });
  });

  it("hideErrorOverlay()", () => {
    const hideStub = sinon.stub(ErrorOverlay, "hide");

    LiveReload.hideErrorOverlay();

    sinon.assert.calledOnceWithExactly(hideStub, OVERLAY_ID);
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

  describe("removePhoenixReloader()", () => {
    const useDocument = (body) => {
      const {window} = new JSDOM(
        `<!DOCTYPE html><html><head></head><body>${body}</body></html>`,
      );

      globalThis.document = window.document;
    };

    beforeEach(() => {
      globalThis.Hologram.config.liveReload = true;
    });

    const iframeSrcs = () =>
      Array.from(document.querySelectorAll("iframe")).map((iframe) =>
        iframe.getAttribute("src"),
      );

    it("removes Phoenix's live reload iframe", () => {
      useDocument(
        '<div id="app"></div><iframe hidden height="0" width="0" src="/phoenix/live_reload/frame"></iframe>',
      );

      LiveReload.removePhoenixReloader();

      assert.deepStrictEqual(iframeSrcs(), []);
      assert.isNotNull(document.getElementById("app"));
    });

    it("removes it under an endpoint path prefix and with a suffix", () => {
      useDocument(
        '<iframe src="/app/phoenix/live_reload/frame"></iframe>' +
          '<iframe src="/phoenix/live_reload/frame/proxied/app/path"></iframe>',
      );

      LiveReload.removePhoenixReloader();

      assert.deepStrictEqual(iframeSrcs(), []);
    });

    it("leaves other iframes", () => {
      useDocument('<iframe src="https://www.youtube.com/embed/abc"></iframe>');

      LiveReload.removePhoenixReloader();

      assert.deepStrictEqual(iframeSrcs(), [
        "https://www.youtube.com/embed/abc",
      ]);
    });

    it("leaves it where live reload does not run", () => {
      globalThis.Hologram.config.liveReload = false;

      useDocument('<iframe src="/phoenix/live_reload/frame"></iframe>');

      LiveReload.removePhoenixReloader();

      assert.deepStrictEqual(iframeSrcs(), ["/phoenix/live_reload/frame"]);
    });
  });

  describe("snapshotFits()", () => {
    const snapshot = {pageDigest: "page-1", runtimeDigest: "runtime-1"};

    beforeEach(() => {
      globalThis.Hologram.config.liveReload = true;
    });

    it("the code it was taken with", () => {
      assert.isTrue(LiveReload.snapshotFits(snapshot, "page-1", "runtime-1"));
    });

    it("another page bundle", () => {
      assert.isFalse(LiveReload.snapshotFits(snapshot, "page-2", "runtime-1"));
    });

    it("another runtime bundle", () => {
      assert.isFalse(LiveReload.snapshotFits(snapshot, "page-1", "runtime-2"));
    });

    it("a snapshot with no stamp", () => {
      assert.isTrue(LiveReload.snapshotFits({}, "page-2", "runtime-2"));
    });

    it("a snapshot stamped with no page bundle", () => {
      assert.isTrue(
        LiveReload.snapshotFits(
          {pageDigest: null, runtimeDigest: "runtime-1"},
          "page-2",
          "runtime-2",
        ),
      );
    });

    it("other code, where live reload does not run", () => {
      globalThis.Hologram.config.liveReload = false;

      assert.isTrue(LiveReload.snapshotFits(snapshot, "page-2", "runtime-2"));
    });
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

  describe("swapStylesheets()", () => {
    const originalMutationObserver = globalThis.MutationObserver;

    let clock;
    let window;

    const html = (head) =>
      `<!DOCTYPE html><html><head>${head}</head><body></body></html>`;

    const links = () => Array.from(document.querySelectorAll("link"));

    const load = (element) => element.dispatchEvent(new window.Event("load"));

    const fail = (element) => element.dispatchEvent(new window.Event("error"));

    // Lets the mutation observers see what changed.
    const settle = () => new Promise((resolve) => setImmediate(resolve));

    const useDocument = (head) => {
      ({window} = new JSDOM(html(head), {url: "http://localhost:4000/page"}));
      globalThis.document = window.document;
      globalThis.MutationObserver = window.MutationObserver;
    };

    beforeEach(() => {
      clock = sinon.useFakeTimers({now: 1_000, toFake: ["Date"]});
    });

    afterEach(() => {
      globalThis.MutationObserver = originalMutationObserver;
    });

    it("loads a copy of the stylesheet from a fresh URL right after it", () => {
      useDocument('<link rel="stylesheet" href="/assets/app.css">');
      const [link] = links();

      LiveReload.swapStylesheets();

      const [, copy] = links();

      assert.equal(link.getAttribute("href"), "/assets/app.css");
      assert.equal(copy.rel, "stylesheet");
      assert.match(
        copy.href,
        /^http:\/\/localhost:4000\/assets\/app\.css\?_hologram_css=1000-\d+$/,
      );
    });

    it("gives the stylesheet the fresh URL once the copy loads", () => {
      useDocument('<link rel="stylesheet" href="/assets/app.css">');

      LiveReload.swapStylesheets();
      const [link, copy] = links();
      load(copy);

      assert.equal(link.href, copy.href);
      assert.equal(links().length, 2);
    });

    it("removes the copy once the stylesheet loads", () => {
      useDocument('<link rel="stylesheet" href="/assets/app.css">');

      LiveReload.swapStylesheets();
      const [link, copy] = links();
      load(copy);
      load(link);

      assert.deepStrictEqual(links(), [link]);
    });

    it("removes the copy when the stylesheet fails to load", () => {
      useDocument('<link rel="stylesheet" href="/assets/app.css">');

      LiveReload.swapStylesheets();
      const [link, copy] = links();
      load(copy);
      fail(link);

      assert.deepStrictEqual(links(), [link]);
    });

    it("leaves the stylesheet as it is when the copy fails to load", () => {
      useDocument('<link rel="stylesheet" href="/assets/app.css">');

      LiveReload.swapStylesheets();
      const [link, copy] = links();
      fail(copy);

      assert.equal(link.getAttribute("href"), "/assets/app.css");
      assert.deepStrictEqual(links(), [link]);
    });

    it("keeps the URL's other query params and replaces an earlier swap's", () => {
      useDocument(
        '<link rel="stylesheet" href="/assets/app.css?v=2&_hologram_css=1">',
      );

      LiveReload.swapStylesheets();
      const [, copy] = links();
      const url = new URL(copy.href);

      assert.equal(url.searchParams.get("v"), "2");
      assert.match(url.searchParams.get("_hologram_css"), /^1000-\d+$/);
    });

    it("gives two swaps in the same millisecond different URLs", () => {
      useDocument('<link rel="stylesheet" href="/assets/app.css">');
      const [link] = links();

      LiveReload.swapStylesheets();
      const [, firstCopy] = links();
      load(firstCopy);
      load(link);
      const firstUrl = link.href;

      LiveReload.swapStylesheets();
      const [, secondCopy] = links();

      assert.notEqual(secondCopy.href, firstUrl);
    });

    it("leaves stylesheets marked data-no-reload, from another origin, and other links alone", () => {
      useDocument(
        '<link rel="stylesheet" href="/assets/admin.css" data-no-reload>' +
          '<link rel="stylesheet" href="https://cdn.example.com/lib.css">' +
          '<link rel="icon" href="/favicon.ico">',
      );

      LiveReload.swapStylesheets();

      assert.equal(links().length, 3);
    });

    it("swaps every stylesheet of the page's origin", () => {
      useDocument(
        '<link rel="stylesheet" href="/assets/app.css">' +
          '<link rel="stylesheet" href="http://localhost:4000/assets/admin.css">',
      );

      LiveReload.swapStylesheets();

      assert.equal(links().length, 4);
    });

    it("tells the page's origin by the page's URL, not by a base URL", () => {
      useDocument(
        '<base href="https://cdn.example.com/">' +
          '<link rel="stylesheet" href="http://localhost:4000/assets/app.css">' +
          '<link rel="stylesheet" href="lib.css">',
      );

      LiveReload.swapStylesheets();
      const [, copy] = links();

      assert.equal(links().length, 3);
      assert.match(copy.href, /^http:\/\/localhost:4000\/assets\/app\.css\?/);
    });

    it("gives a disabled stylesheet the fresh URL right away, with no copy", () => {
      useDocument('<link rel="stylesheet" href="/assets/theme.css" disabled>');
      const [link] = links();

      LiveReload.swapStylesheets();

      assert.deepStrictEqual(links(), [link]);
      assert.match(link.href, /_hologram_css=1000-\d+$/);
    });

    it("gives a stylesheet disabled through its style sheet the fresh URL, and disables it again", () => {
      useDocument('<link rel="stylesheet" href="/assets/theme.css">');
      const [link] = links();
      const sheet = {disabled: true};
      Object.defineProperty(link, "sheet", {get: () => sheet});

      LiveReload.swapStylesheets();
      sheet.disabled = false;
      load(link);

      assert.deepStrictEqual(links(), [link]);
      assert.match(link.href, /_hologram_css=1000-\d+$/);
      assert.isTrue(sheet.disabled);
    });

    it("gives the copy the stylesheet's nonce, which the browser hides", () => {
      useDocument(
        '<link rel="stylesheet" href="/assets/app.css" nonce="abc123">',
      );
      const [link] = links();

      Object.defineProperty(link, "nonce", {value: "abc123"});
      link.setAttribute("nonce", "");

      LiveReload.swapStylesheets();
      const [, copy] = links();

      assert.equal(copy.nonce, "abc123");
    });

    it("swaps again once done when asked to meanwhile, with a newer URL", () => {
      useDocument('<link rel="stylesheet" href="/assets/app.css">');

      LiveReload.swapStylesheets();
      const [link, firstCopy] = links();

      clock.tick(5);
      LiveReload.swapStylesheets();

      assert.equal(links().length, 2);

      load(firstCopy);
      load(link);

      const [, secondCopy] = links();

      assert.notEqual(secondCopy, firstCopy);
      assert.match(secondCopy.href, /_hologram_css=1005-\d+$/);
    });

    it("runs one swap at a time, whatever events earlier swaps left unanswered", () => {
      useDocument('<link rel="stylesheet" href="/assets/app.css">');

      LiveReload.swapStylesheets();
      const [link, firstCopy] = links();
      load(firstCopy);
      load(link);

      LiveReload.swapStylesheets();
      const [, secondCopy] = links();
      load(secondCopy);
      LiveReload.swapStylesheets();
      fail(link);

      LiveReload.swapStylesheets();

      assert.equal(links().length, 2);
    });

    it("leaves no copy behind when the stylesheet is removed before the copy loads", async () => {
      useDocument('<link rel="stylesheet" href="/assets/app.css">');

      LiveReload.swapStylesheets();
      const [link, copy] = links();
      link.remove();
      await settle();
      load(copy);

      assert.deepStrictEqual(links(), []);
    });

    it("leaves no copy behind when the stylesheet is removed while it loads", async () => {
      useDocument('<link rel="stylesheet" href="/assets/app.css">');

      LiveReload.swapStylesheets();
      const [link, copy] = links();
      load(copy);
      link.remove();
      await settle();

      assert.deepStrictEqual(links(), []);
    });

    it("swaps a stylesheet a render recreated when asked to meanwhile", async () => {
      useDocument('<link rel="stylesheet" href="/assets/app.css">');

      LiveReload.swapStylesheets();
      const [link] = links();
      LiveReload.swapStylesheets();

      const recreatedLink = link.cloneNode();
      link.replaceWith(recreatedLink);
      await settle();

      const [first, recreatedCopy] = links();

      assert.equal(first, recreatedLink);
      assert.match(recreatedCopy.href, /_hologram_css=/);
    });

    describe("with the app's asset paths", () => {
      const copyPath = (copy) => new URL(copy.href).pathname;

      beforeEach(() => {
        AssetPathRegistry.populate({
          "assets/app.css": "/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css",
          "assets/admin.css": "/assets/admin.css",
          "hologram/runtime.js": "/hologram/runtime-AAAAAAAA.js",
        });
      });

      afterEach(() => {
        AssetPathRegistry.entries = null;
        AssetPathRegistry.manifest = null;
        delete globalThis.Hologram.assetManifest;
      });

      it("swaps a stylesheet whose asset path changed to the new path", () => {
        useDocument(
          '<link rel="stylesheet" href="/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css">',
        );

        LiveReload.swapStylesheets({
          "assets/app.css": "/assets/app.css",
          "assets/admin.css": "/assets/admin.css",
        });

        const [, copy] = links();

        assert.match(
          copy.href,
          /^http:\/\/localhost:4000\/assets\/app\.css\?_hologram_css=1000-\d+$/,
        );
      });

      it("keeps the path of a stylesheet whose asset path didn't change", () => {
        useDocument('<link rel="stylesheet" href="/assets/admin.css">');

        LiveReload.swapStylesheets({
          "assets/app.css": "/assets/app.css",
          "assets/admin.css": "/assets/admin.css",
        });

        const [, copy] = links();

        assert.equal(copyPath(copy), "/assets/admin.css");
      });

      it("gives the asset path registry the app's new asset paths and keeps Hologram's bundles", () => {
        useDocument("");

        LiveReload.swapStylesheets({
          "assets/app.css": "/assets/app.css",
          "assets/new.css": "/assets/new.css",
        });

        assert.deepStrictEqual(AssetPathRegistry.manifest, {
          "assets/app.css": "/assets/app.css",
          "assets/new.css": "/assets/new.css",
          "hologram/runtime.js": "/hologram/runtime-AAAAAAAA.js",
        });

        assert.deepStrictEqual(
          AssetPathRegistry.lookup(Type.bitstring("assets/app.css")),
          Type.bitstring("/assets/app.css"),
        );
      });

      it("swaps again to the new path when the path changes while a swap runs", () => {
        useDocument(
          '<link rel="stylesheet" href="/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css">',
        );

        LiveReload.swapStylesheets({
          "assets/app.css": "/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css",
        });

        const [link, firstCopy] = links();

        LiveReload.swapStylesheets({"assets/app.css": "/assets/app.css"});

        load(firstCopy);
        load(link);

        const [, secondCopy] = links();

        assert.equal(
          copyPath(firstCopy),
          "/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css",
        );
        assert.equal(copyPath(secondCopy), "/assets/app.css");
      });

      it("swaps a stylesheet still linked by an older path to the newest one", () => {
        useDocument(
          '<link rel="stylesheet" href="/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css">',
        );

        LiveReload.swapStylesheets({
          "assets/app.css": "/assets/app-96c15c2bb2921193bf290df8cd85e2ba.css",
        });

        const [link, firstCopy] = links();
        fail(firstCopy);

        LiveReload.swapStylesheets({"assets/app.css": "/assets/app.css"});

        const [, secondCopy] = links();

        assert.equal(
          link.getAttribute("href"),
          "/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css",
        );

        assert.equal(copyPath(secondCopy), "/assets/app.css");
      });

      it("populates the asset path registry from the document's manifest first when it hasn't been", () => {
        AssetPathRegistry.entries = null;
        AssetPathRegistry.manifest = null;

        globalThis.Hologram.assetManifest = {
          "assets/app.css": "/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css",
          "hologram/runtime.js": "/hologram/runtime-AAAAAAAA.js",
        };

        useDocument(
          '<link rel="stylesheet" href="/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css">',
        );

        LiveReload.swapStylesheets({"assets/app.css": "/assets/app.css"});

        const [, copy] = links();

        assert.equal(copyPath(copy), "/assets/app.css");

        assert.deepStrictEqual(AssetPathRegistry.manifest, {
          "assets/app.css": "/assets/app.css",
          "hologram/runtime.js": "/hologram/runtime-AAAAAAAA.js",
        });
      });

      it("leaves the document's manifest as it is", () => {
        const assetManifest = {
          "assets/app.css": "/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css",
          "hologram/runtime.js": "/hologram/runtime-AAAAAAAA.js",
        };

        globalThis.Hologram.assetManifest = assetManifest;
        AssetPathRegistry.populate(assetManifest);
        useDocument("");

        LiveReload.swapStylesheets({"assets/app.css": "/assets/app.css"});

        assert.deepStrictEqual(globalThis.Hologram.assetManifest, {
          "assets/app.css": "/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css",
          "hologram/runtime.js": "/hologram/runtime-AAAAAAAA.js",
        });
      });

      it("swaps a stylesheet linked by a path the asset path registry no longer holds to the one it holds", () => {
        AssetPathRegistry.populate({"assets/app.css": "/assets/app.css"});

        useDocument(
          '<link rel="stylesheet" href="/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css">',
        );

        LiveReload.swapStylesheets({"assets/app.css": "/assets/app.css"});

        const [, copy] = links();

        assert.equal(copyPath(copy), "/assets/app.css");
      });

      it("leaves the asset path registry as it is with no asset paths given", () => {
        useDocument(
          '<link rel="stylesheet" href="/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css">',
        );

        LiveReload.swapStylesheets();

        const [, copy] = links();

        assert.equal(
          copyPath(copy),
          "/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css",
        );

        assert.deepStrictEqual(AssetPathRegistry.manifest, {
          "assets/app.css": "/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css",
          "assets/admin.css": "/assets/admin.css",
          "hologram/runtime.js": "/hologram/runtime-AAAAAAAA.js",
        });
      });

      it("reads a path with encoded characters", () => {
        useDocument(
          '<link rel="stylesheet" href="/assets/my%20app-0f5f13cf0b14c88bd431ef163b63d68d.css">',
        );

        LiveReload.swapStylesheets({"assets/my app.css": "/assets/my app.css"});

        const [, copy] = links();

        assert.equal(copyPath(copy), "/assets/my%20app.css");
      });

      it("leaves a stylesheet whose path can't be decoded at its path", () => {
        useDocument('<link rel="stylesheet" href="/assets/app%zz.css">');

        LiveReload.swapStylesheets({"assets/app.css": "/assets/app.css"});

        const [, copy] = links();

        assert.equal(copyPath(copy), "/assets/app%zz.css");
      });

      it("keeps the URL's other query params when it swaps to the new path", () => {
        useDocument(
          '<link rel="stylesheet" href="/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css?v=2">',
        );

        LiveReload.swapStylesheets({"assets/app.css": "/assets/app.css"});

        const [, copy] = links();
        const url = new URL(copy.href);

        assert.equal(url.pathname, "/assets/app.css");
        assert.equal(url.searchParams.get("v"), "2");
      });

      it("gives a disabled stylesheet the new path right away", () => {
        useDocument(
          '<link rel="stylesheet" href="/assets/app-0f5f13cf0b14c88bd431ef163b63d68d.css" disabled>',
        );

        const [link] = links();

        LiveReload.swapStylesheets({"assets/app.css": "/assets/app.css"});

        assert.equal(new URL(link.href).pathname, "/assets/app.css");
      });

      it("leaves a copy served under its own name, with no asset of its own name in the registry, at its path", () => {
        useDocument(
          '<link rel="stylesheet" href="/assets/gone-0f5f13cf0b14c88bd431ef163b63d68d.css">',
        );

        LiveReload.swapStylesheets({
          "assets/gone-0f5f13cf0b14c88bd431ef163b63d68d.css":
            "/assets/gone-0f5f13cf0b14c88bd431ef163b63d68d.css",
        });

        const [, copy] = links();

        assert.equal(
          copyPath(copy),
          "/assets/gone-0f5f13cf0b14c88bd431ef163b63d68d.css",
        );
      });
    });
  });
});
