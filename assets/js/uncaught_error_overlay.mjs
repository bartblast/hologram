"use strict";

import ErrorOverlay from "./error_overlay.mjs";

const OVERLAY_ID = "hologram-uncaught-error-overlay";

// The apps a frame comes from when it isn't the page's own code. Frames from
// these read in one tone throughout, so the app's own frames stand out of the
// run instead of having to be found in it. A frame naming no app is taken to
// be the app's own, since an unknown app is likelier to be the page's code
// than the framework under it.
const FRAMEWORK_APPS = new Set([
  "elixir",
  "erts",
  "hologram",
  "kernel",
  "stdlib",
]);

// A frame as Exception.format_stacktrace_entry/1 writes it, in the parts it
// reads in: what indents it, the app it came from when known, where in the
// source when known, and what was running there.
const FRAME_REGEX = /^(\s*)(\([^)]*\)\s+)?(\S.*?:\d+:\s+)?(.*)$/;

// Where the stacktrace starts: the first line placing something in a source
// file. A message can run over several lines and indent them - the arguments a
// FunctionClauseError lists, for one - so indentation alone doesn't say where
// the message ends.
const FRAME_START_REGEX = /^ {4}.*:\d+: /;

// The overlay reporting an uncaught client error in the page. Dismissable,
// since a runtime error often leaves the rest of the page usable.
//
// The report is the one the console gets, read into the tones the overlay
// renders: what was raised, then a frame at a time, each split into where it
// came from and what was running there.
export default class UncaughtErrorOverlay {
  static hide() {
    ErrorOverlay.hide(OVERLAY_ID);
  }

  static show(report) {
    ErrorOverlay.show({
      content: $.#toLines(report),
      dismissable: true,
      heading: "Runtime Error",
      id: OVERLAY_ID,
    });
  }

  static #toFrameSegments(line) {
    const [, indent, app, location, running] = line.match(FRAME_REGEX);
    const appName = app ? app.slice(1).split(" ")[0] : null;

    if (appName !== null && FRAMEWORK_APPS.has(appName)) {
      return [{text: line, tone: "chrome"}];
    }

    const segments = [{text: indent + (app ?? ""), tone: "chrome"}];

    if (location !== undefined) {
      segments.push({text: location, tone: "meta"});
    }

    segments.push({text: running, tone: "body"});

    return segments;
  }

  static #toLines(report) {
    // A stacktrace closes with a newline of its own, which would otherwise
    // render as a line with nothing on it.
    const lines = report.trimEnd().split("\n");

    const firstFrame = lines.findIndex((line) => FRAME_START_REGEX.test(line));

    // A message the runtime couldn't place carries no frames to set it against.
    if (firstFrame === -1) {
      return [[{text: lines.join("\n"), tone: "banner"}]];
    }

    // The message is kept as one line, newlines and all, so a message running
    // over several of them is set apart from the frames once rather than
    // broken up by the spacing that does it.
    const message = lines.slice(0, firstFrame).join("\n").trimEnd();

    const frames = lines
      .slice(firstFrame)
      .map((line) => $.#toFrameSegments(line));

    return [[{text: message, tone: "banner"}], ...frames];
  }
}

const $ = UncaughtErrorOverlay;
