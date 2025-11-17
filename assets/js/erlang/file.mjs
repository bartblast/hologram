"use strict";

import Type from "../type.mjs";
import Erlang_Filename from "./filename.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_File = {
  // Start basename/1
  "basename/1": (filename) => {
    // Delegate to filename module
    return Erlang_Filename["basename/1"](filename);
  },
  // End basename/1
  // Deps: [:filename.basename/1]

  // Start basename/2
  "basename/2": (filename, ext) => {
    // Delegate to filename module
    return Erlang_Filename["basename/2"](filename, ext);
  },
  // End basename/2
  // Deps: [:filename.basename/2]

  // Start change_group/2
  "change_group/2": (name, group) => {
    // File system operations are not supported in browser context
    // Return error to match expected behavior
    return Type.tuple([Type.atom("error"), Type.atom("enotsup")]);
  },
  // End change_group/2
  // Deps: []

  // Start change_mode/2
  "change_mode/2": (name, mode) => {
    // File system operations are not supported in browser context
    return Type.tuple([Type.atom("error"), Type.atom("enotsup")]);
  },
  // End change_mode/2
  // Deps: []

  // Start change_owner/2
  "change_owner/2": (name, owner) => {
    // File system operations are not supported in browser context
    return Type.tuple([Type.atom("error"), Type.atom("enotsup")]);
  },
  // End change_owner/2
  // Deps: []

  // Start copy/2
  "copy/2": (source, destination) => {
    // File copying is not supported in browser context
    return Type.tuple([Type.atom("error"), Type.atom("enotsup")]);
  },
  // End copy/2
  // Deps: []

  // Start copy/3
  "copy/3": (source, destination, bytesCount) => {
    // File copying is not supported in browser context
    return Type.tuple([Type.atom("error"), Type.atom("enotsup")]);
  },
  // End copy/3
  // Deps: []
};

export default Erlang_File;
