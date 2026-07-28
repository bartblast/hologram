"use strict";

import Type from "../type.mjs";

// Shadow call stack of Elixir-level frames. Native JS stacks cannot yield Elixir-shaped frames -
// function names are minified, line numbers point into generated code, and frames are truncated
// across awaits - so the interpreter maintains its own stack, pushing a frame when it dispatches a
// function and popping it in a finally block so raises unwind the stack correctly.
//
// Frames are cheap plain objects {module, function, arityOrArgs, file, line, errorInfo}, converted
// to boxed Erlang terms only when a trace is captured or formatted, never on the hot path.
//
// Actions execute sequentially, so a single global stack is sufficient. When the BEAM process model
// moves to web workers, this becomes per-process state.
export default class CallStack {
  static #frames = [];

  // Converts a frame to the boxed Erlang stacktrace entry tuple
  // {module, function, arity_or_args, location}. The location is a keyword list with :file,
  // :line and :error_info entries - each present only when the frame carries the datum, in that
  // order, matching the BEAM. Transpiled Elixir exception machinery consumes the result unmodified.
  static boxFrame(frame) {
    let moduleTerm;

    if (frame.module === null) {
      moduleTerm = Type.nil();
    } else if (/^[A-Z]/.test(frame.module)) {
      moduleTerm = Type.alias(frame.module);
    } else {
      moduleTerm = Type.atom(frame.module);
    }

    const functionTerm =
      frame.function === null ? Type.nil() : Type.atom(frame.function);

    let arityOrArgsTerm;

    if (frame.arityOrArgs === null) {
      arityOrArgsTerm = Type.nil();
    } else if (typeof frame.arityOrArgs === "number") {
      arityOrArgsTerm = Type.integer(frame.arityOrArgs);
    } else {
      arityOrArgsTerm = frame.arityOrArgs;
    }

    const location = [];

    if (frame.file !== null) {
      location.push(Type.tuple([Type.atom("file"), Type.charlist(frame.file)]));
    }

    if (frame.line !== null) {
      location.push(Type.tuple([Type.atom("line"), Type.integer(frame.line)]));
    }

    if (frame.errorInfo !== null) {
      location.push(Type.tuple([Type.atom("error_info"), frame.errorInfo]));
    }

    return Type.tuple([
      moduleTerm,
      functionTerm,
      arityOrArgsTerm,
      Type.list(location),
    ]);
  }

  // Returns the innermost frame without removing it, or undefined when the stack is empty.
  static peek() {
    return $.#frames.at(-1);
  }

  // Removes the innermost frame and returns it, or undefined when the stack is empty.
  static pop() {
    return $.#frames.pop();
  }

  // Adds a frame as the new innermost one.
  static push(frame) {
    $.#frames.push(frame);
  }

  // Clears the stack.
  static reset() {
    $.#frames = [];
  }

  // Returns the current frames, innermost first, matching Erlang stacktrace order. The array is a
  // copy, so later pushes and pops leave it untouched. Frames are shared by reference rather than
  // cloned - once a function's body starts executing its frame is no longer mutated (the dispatch
  // fills in the line between push and body execution, when a clause matches).
  static snapshot() {
    return $.#frames.slice().reverse();
  }
}

const $ = CallStack;
