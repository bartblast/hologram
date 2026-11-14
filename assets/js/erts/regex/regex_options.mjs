"use strict";

import {NEWLINE_VERBS} from "./regex_newlines.mjs";

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

// Returns what a parsed pattern's start-of-pattern option verbs set, each
// field left out when no verb sets it: newline and bsr_anycrlf hold the last
// verb's value and beat the matching compile option, unicode is true when a
// UTF verb is present, and matchLimit and matchLimitRecursion hold the lowest
// value among their verbs. The limits matter only to the interpreter, which
// takes the lower of a limit verb and the run limit, and uses a limit verb in
// place of the default when no run limit is given.
export function startOptionSettings(ast) {
  const settings = {};

  for (const item of startOptions(ast)) {
    if (NEWLINE_VERBS[item.name] !== undefined) {
      settings.newline = NEWLINE_VERBS[item.name];
    } else if (item.name === "BSR_ANYCRLF") {
      settings.bsr_anycrlf = true;
    } else if (item.name === "BSR_UNICODE") {
      settings.bsr_anycrlf = false;
    } else if (item.name === "LIMIT_DEPTH" || item.name === "LIMIT_RECURSION") {
      // LIMIT_RECURSION is the obsolete PCRE2 synonym of LIMIT_DEPTH
      settings.matchLimitRecursion = Math.min(
        settings.matchLimitRecursion ?? Infinity,
        item.value,
      );
    } else if (item.name === "LIMIT_MATCH") {
      settings.matchLimit = Math.min(
        settings.matchLimit ?? Infinity,
        item.value,
      );
    } else if (item.name === "UTF" || item.name === "UTF8") {
      settings.unicode = true;
    }
  }

  return settings;
}

// Yields the leading start-option items of a parsed pattern.
export function* startOptions(ast) {
  if (ast.type !== "concatenation") return;

  for (const item of ast.items) {
    if (item.type !== "startOption") return;

    yield item;
  }
}
