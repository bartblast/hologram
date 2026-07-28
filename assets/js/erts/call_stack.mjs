"use strict";

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
  // copy, so later pushes and pops leave it untouched. Frames are never mutated after being pushed,
  // so they are shared by reference rather than cloned.
  static snapshot() {
    return $.#frames.slice().reverse();
  }
}

const $ = CallStack;
