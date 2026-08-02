"use strict";

import {assert, defineRuntimeGlobals, sinon} from "./support/helpers.mjs";

import ERTS from "../../assets/js/erts.mjs";
import ErrorOverlay from "../../assets/js/error_overlay.mjs";
import HologramBoxedError from "../../assets/js/errors/boxed_error.mjs";
import Type from "../../assets/js/type.mjs";
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

    const fileEntry = (path) =>
      Type.tuple([Type.atom("file"), Type.charlist(path)]);

    const lineEntry = (line) =>
      Type.tuple([Type.atom("line"), Type.integer(line)]);

    const frame = (moduleTerm, functionName, arity, location) =>
      Type.tuple([
        moduleTerm,
        Type.atom(functionName),
        Type.integer(arity),
        Type.list(location),
      ]);

    const errorWith = (frames, message = "my message") => {
      const error = new HologramBoxedError(
        Type.errorStruct("MyError", message),
      );

      error.stacktrace = Type.list(frames);

      return error;
    };

    const contentOf = (error) => {
      UncaughtErrorOverlay.show(error);

      return showStub.firstCall.args[0].content;
    };

    beforeEach(() => {
      showStub = sinon.stub(ErrorOverlay, "show");
    });

    afterEach(() => {
      ERTS.appVersions = {};
      ERTS.moduleMetadata = {};
      showStub.restore();
    });

    it("puts up a dismissable overlay under its own id", () => {
      UncaughtErrorOverlay.show(errorWith([]));

      sinon.assert.calledOnceWithExactly(showStub, {
        content: [[{text: "** (MyError) my message", tone: "banner"}]],
        dismissable: true,
        heading: "Runtime Error",
        id: OVERLAY_ID,
      });
    });

    it("reads an error carrying no frames as the message alone", () => {
      assert.deepStrictEqual(contentOf(errorWith([])), [
        [{text: "** (MyError) my message", tone: "banner"}],
      ]);
    });

    // A FunctionClauseError's message lists the arguments it was given over
    // several lines, and stays the one thing the frames are set against.
    it("keeps a message running over several lines in one piece", () => {
      const message = "my message\n\n    # 1\n    :not_a_tuple";

      assert.deepStrictEqual(contentOf(errorWith([], message)), [
        [{text: `** (MyError) ${message}`, tone: "banner"}],
      ]);
    });

    it("sets a frame's source location apart from what was running", () => {
      const frames = [
        frame(Type.alias("MyModule"), "my_fun", 1, [
          fileEntry("lib/my_module.ex"),
          lineEntry(11),
        ]),
      ];

      assert.deepStrictEqual(contentOf(errorWith(frames))[1], [
        {text: "    ", tone: "chrome"},
        {text: "lib/my_module.ex:11: ", tone: "meta"},
        {text: "MyModule.my_fun/1", tone: "body"},
      ]);
    });

    it("names the application a frame the app owns came from", () => {
      ERTS.moduleMetadata = {MyModule: {app: "my_app", file: null}};
      ERTS.appVersions = {my_app: "1.2.3"};

      const frames = [
        frame(Type.alias("MyModule"), "my_fun", 1, [
          fileEntry("lib/my_module.ex"),
          lineEntry(11),
        ]),
      ];

      assert.deepStrictEqual(contentOf(errorWith(frames))[1], [
        {text: "    (my_app 1.2.3) ", tone: "chrome"},
        {text: "lib/my_module.ex:11: ", tone: "meta"},
        {text: "MyModule.my_fun/1", tone: "body"},
      ]);
    });

    it("reads a frame from outside the app in one tone throughout", () => {
      ERTS.moduleMetadata = {"Hologram.Runtime": {app: "hologram", file: null}};
      ERTS.appVersions = {hologram: "0.9.3"};

      const frames = [
        frame(Type.alias("Hologram.Runtime"), "run", 1, [
          fileEntry("lib/hologram/runtime.ex"),
          lineEntry(12),
        ]),
      ];

      assert.deepStrictEqual(contentOf(errorWith(frames))[1], [
        {
          text: "    (hologram 0.9.3) lib/hologram/runtime.ex:12: Hologram.Runtime.run/1",
          tone: "chrome",
        },
      ]);
    });

    it("places a frame naming a file but no line by its file alone", () => {
      const frames = [
        frame(Type.alias("MyModule"), "my_fun", 1, [
          fileEntry("lib/my_module.ex"),
        ]),
      ];

      assert.deepStrictEqual(contentOf(errorWith(frames))[1], [
        {text: "    ", tone: "chrome"},
        {text: "lib/my_module.ex: ", tone: "meta"},
        {text: "MyModule.my_fun/1", tone: "body"},
      ]);
    });

    it("reads a frame placing no source as what was running alone", () => {
      const frames = [frame(Type.alias("MyModule"), "my_fun", 1, [])];

      assert.deepStrictEqual(contentOf(errorWith(frames))[1], [
        {text: "    ", tone: "chrome"},
        {text: "MyModule.my_fun/1", tone: "body"},
      ]);
    });
  });
});
