"use strict";

import ErrorOverlay from "./error_overlay.mjs";
import Interpreter from "./interpreter.mjs";
import Stacktrace from "./stacktrace.mjs";

const OVERLAY_ID = "hologram-uncaught-error-overlay";

// The applications a frame comes from when it isn't the page's own code. Frames
// from these read in one tone throughout, so the app's own frames stand out of
// the run instead of having to be found in it. A frame naming no application is
// taken to be the app's own, since an unknown one is likelier to be the page's
// code than the framework under it.
const FRAMEWORK_APPS = new Set([
  "elixir",
  "erts",
  "hologram",
  "kernel",
  "stdlib",
]);

// The overlay reporting an uncaught client error in the page. Dismissable,
// since a runtime error often leaves the rest of the page usable.
//
// What it shows is what the console shows, in the tones it renders: what was
// raised, then a frame at a time, each split into where it came from and what
// was running there. Those parts are taken from the frames as data rather than
// read back out of the rendered report - the rendering is Elixir's shape, and
// telling a message from the frames below it, or a location from what follows
// it, is what reading that shape can't do reliably. A FunctionClauseError
// indents the arguments it lists exactly as a frame is indented.
export default class UncaughtErrorOverlay {
  static hide() {
    ErrorOverlay.hide(OVERLAY_ID);
  }

  static show(error) {
    ErrorOverlay.show({
      content: $.#toLines(error),
      dismissable: true,
      heading: "Runtime Error",
      id: OVERLAY_ID,
    });
  }

  static #toFrameSegments(frame) {
    const {app, appName, location, running} = Stacktrace.frameParts(frame);

    if (appName !== null && FRAMEWORK_APPS.has(appName)) {
      return [{text: `    ${app}${location}${running}`, tone: "chrome"}];
    }

    const segments = [{text: `    ${app}`, tone: "chrome"}];

    if (location !== "") {
      segments.push({text: location, tone: "meta"});
    }

    segments.push({text: running, tone: "body"});

    return segments;
  }

  static #toLines(error) {
    // The message is one line, newlines and all, so a message running over
    // several of them is set apart from the frames once rather than broken up
    // by the spacing that does it.
    const message = [{text: `** ${error.message}`, tone: "banner"}];

    const frames = Interpreter.boxStacktrace(error).data.map((frame) =>
      $.#toFrameSegments(frame),
    );

    return [message, ...frames];
  }
}

const $ = UncaughtErrorOverlay;
