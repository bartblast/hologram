"use strict";

// Returns a copy of the flags updated by an option setting's letters.
// The x, J, n and ASCII option letters only affect parsing and are already
// handled by the parser.
export function applyOptionSetting(flags, node) {
  const next = {...flags};

  // (?^ resets i, m, n, s and x to their defaults
  if (node.reset) {
    next.caseless = false;
    next.dotall = false;
    next.multiline = false;
  }

  if (node.set.includes("i")) next.caseless = true;
  if (node.set.includes("m")) next.multiline = true;
  if (node.set.includes("s")) next.dotall = true;
  if (node.set.includes("U")) next.ungreedy = true;

  if (node.unset.includes("i")) next.caseless = false;
  if (node.unset.includes("m")) next.multiline = false;
  if (node.unset.includes("s")) next.dotall = false;
  if (node.unset.includes("U")) next.ungreedy = false;

  return next;
}
