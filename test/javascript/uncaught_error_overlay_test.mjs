"use strict";

import {assert, defineRuntimeGlobals, sinon} from "./support/helpers.mjs";

import ErrorOverlay from "../../assets/js/error_overlay.mjs";
import UncaughtErrorOverlay from "../../assets/js/uncaught_error_overlay.mjs";

defineRuntimeGlobals();

const OVERLAY_ID = "hologram-uncaught-error-overlay";

describe("UncaughtErrorOverlay", () => {
  it("hide()", () => {
    const hideStub = sinon.stub(ErrorOverlay, "hide");

    UncaughtErrorOverlay.hide();

    sinon.assert.calledOnceWithExactly(hideStub, OVERLAY_ID);

    hideStub.restore();
  });

  describe("show()", () => {
    let showStub;

    const contentOf = (report) => {
      UncaughtErrorOverlay.show(report);

      return showStub.firstCall.args[0].content;
    };

    beforeEach(() => {
      showStub = sinon.stub(ErrorOverlay, "show");
    });

    afterEach(() => {
      showStub.restore();
    });

    it("puts up a dismissable overlay under its own id", () => {
      UncaughtErrorOverlay.show("** (RuntimeError) my error");

      sinon.assert.calledOnceWithExactly(showStub, {
        content: [[{text: "** (RuntimeError) my error", tone: "banner"}]],
        dismissable: true,
        heading: "Runtime Error",
        id: OVERLAY_ID,
      });
    });

    it("reads a report carrying no frames as the message alone", () => {
      assert.deepStrictEqual(contentOf("** (RuntimeError) my error"), [
        [{text: "** (RuntimeError) my error", tone: "banner"}],
      ]);
    });

    it("sets the message apart from the frames", () => {
      const report = [
        "** (RuntimeError) my error",
        "    my_app/page.ex:33: MyApp.Page.my_fun/2",
      ].join("\n");

      assert.deepStrictEqual(contentOf(report), [
        [{text: "** (RuntimeError) my error", tone: "banner"}],
        [
          {text: "    ", tone: "chrome"},
          {text: "my_app/page.ex:33: ", tone: "meta"},
          {text: "MyApp.Page.my_fun/2", tone: "body"},
        ],
      ]);
    });

    // A FunctionClauseError lists the arguments it was given, indenting them
    // the way a frame is indented.
    it("keeps a message running over several lines in one piece", () => {
      const report = [
        "** (FunctionClauseError) no function clause matching in MyApp.my_fun/1",
        "",
        "The following arguments were given to MyApp.my_fun/1:",
        "",
        "    # 1",
        "    :abc",
        "",
        "    my_app/page.ex:3: MyApp.my_fun/1",
      ].join("\n");

      const [message, frame] = contentOf(report);

      assert.deepStrictEqual(message, [
        {
          text: [
            "** (FunctionClauseError) no function clause matching in MyApp.my_fun/1",
            "",
            "The following arguments were given to MyApp.my_fun/1:",
            "",
            "    # 1",
            "    :abc",
          ].join("\n"),
          tone: "banner",
        },
      ]);

      assert.deepStrictEqual(frame, [
        {text: "    ", tone: "chrome"},
        {text: "my_app/page.ex:3: ", tone: "meta"},
        {text: "MyApp.my_fun/1", tone: "body"},
      ]);
    });

    // An argument inspected as a map carries a colon of its own, which a frame
    // carries too.
    it("keeps an argument holding a colon in the message", () => {
      const report = [
        "** (FunctionClauseError) no function clause matching in MyApp.my_fun/1",
        "",
        '    %{key: "value"}',
        "",
        "    my_app/page.ex:3: MyApp.my_fun/1",
      ].join("\n");

      const [message] = contentOf(report);

      assert.deepStrictEqual(message, [
        {
          text: [
            "** (FunctionClauseError) no function clause matching in MyApp.my_fun/1",
            "",
            '    %{key: "value"}',
          ].join("\n"),
          tone: "banner",
        },
      ]);
    });

    // A frame raised on entering a function, as a clause mismatch is, names the
    // file it happened in without a line in it.
    it("places a frame naming a file but no line", () => {
      const report = [
        "** (FunctionClauseError) no function clause matching in MyApp.my_fun/1",
        "    (my_app 1.2.3) my_app/page.ex: MyApp.my_fun(:abc)",
      ].join("\n");

      assert.deepStrictEqual(contentOf(report)[1], [
        {text: "    (my_app 1.2.3) ", tone: "chrome"},
        {text: "my_app/page.ex: ", tone: "meta"},
        {text: "MyApp.my_fun(:abc)", tone: "body"},
      ]);
    });

    it("splits an app frame into where it came from and what was running", () => {
      const report = [
        "** (RuntimeError) my error",
        "    (my_app 1.2.3) my_app/page.ex:33: MyApp.Page.my_fun/2",
      ].join("\n");

      assert.deepStrictEqual(contentOf(report)[1], [
        {text: "    (my_app 1.2.3) ", tone: "chrome"},
        {text: "my_app/page.ex:33: ", tone: "meta"},
        {text: "MyApp.Page.my_fun/2", tone: "body"},
      ]);
    });

    it("takes a frame naming no app to be the app's own", () => {
      const report = [
        "** (RuntimeError) my error",
        "    my_app/page.ex:33: MyApp.Page.my_fun/2",
      ].join("\n");

      assert.deepStrictEqual(contentOf(report)[1], [
        {text: "    ", tone: "chrome"},
        {text: "my_app/page.ex:33: ", tone: "meta"},
        {text: "MyApp.Page.my_fun/2", tone: "body"},
      ]);
    });

    it("reads a framework frame in one tone throughout", () => {
      const report = [
        "** (RuntimeError) my error",
        "    (hologram 0.9.3) lib/hologram/runtime.ex:12: Hologram.Runtime.run/1",
        "    (elixir 1.20.0) lib/enum.ex:1725: Enum.map/2",
      ].join("\n");

      assert.deepStrictEqual(contentOf(report).slice(1), [
        [
          {
            text: "    (hologram 0.9.3) lib/hologram/runtime.ex:12: Hologram.Runtime.run/1",
            tone: "chrome",
          },
        ],
        [
          {
            text: "    (elixir 1.20.0) lib/enum.ex:1725: Enum.map/2",
            tone: "chrome",
          },
        ],
      ]);
    });

    it("reads a frame placing no source as what was running there", () => {
      const report = [
        "** (RuntimeError) my error",
        "    my_app/page.ex:33: MyApp.Page.my_fun/2",
        "    (my_app 1.2.3) MyApp.Page.other_fun/0",
      ].join("\n");

      assert.deepStrictEqual(contentOf(report)[2], [
        {text: "    (my_app 1.2.3) ", tone: "chrome"},
        {text: "MyApp.Page.other_fun/0", tone: "body"},
      ]);
    });
  });
});
