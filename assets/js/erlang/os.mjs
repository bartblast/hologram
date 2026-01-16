"use strict";

import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

/**
 * Classifies the OS family and OS name of a given platform string.
 * @param {String} value A platform string.
 * @returns {Object} Object containing family and name attributes.
 */
const classify = (value) => {
  const v = String(value ?? "").toLowerCase();
  if (v.includes("win")) return {family: "win32", name: "nt"};
  if (v.includes("linux")) return {family: "unix", name: "linux"};
  if (v.includes("mac")) return {family: "unix", name: "darwin"};
  if (v.includes("freebsd")) return {family: "unix", name: "freebsd"};
  if (v.includes("openbsd")) return {family: "unix", name: "openbsd"};
  if (v.includes("netbsd")) return {family: "unix", name: "netbsd"};
  if (v.includes("solaris")) return {family: "unix", name: "sunos"};
  if (v.includes("sun")) return {family: "unix", name: "sunos"};
  if (v.includes("aix")) return {family: "unix", name: "aix"};
  if (v.includes("hp-ux")) return {family: "unix", name: "hp-ux"};
  return {}; // TODO: return empty object or null?
};

const Erlang_Os = {
  // Start type/0
  "type/0": () => {
    const platform = navigator.userAgentData?.platform ?? navigator.platform;
    const {family, name} = classify(platform || navigator.userAgent);

    return Type.tuple([Type.atom(family), Type.atom(name)]);
  },
  // End type/0
  // Deps: []
};

export default Erlang_Os;
