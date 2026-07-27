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

// Merges start-of-pattern option verbs into the compile or match options.
// The limit fields matter only to the interpreter, the other consumers
// ignore them.
export function mergeStartOptions(ast, opts) {
  const effectiveOpts = {...opts};

  for (const item of startOptions(ast)) {
    if (NEWLINE_VERBS[item.name] !== undefined) {
      effectiveOpts.newline = NEWLINE_VERBS[item.name];
    } else if (item.name === "BSR_ANYCRLF") {
      effectiveOpts.bsr_anycrlf = true;
    } else if (item.name === "BSR_UNICODE") {
      effectiveOpts.bsr_anycrlf = false;
    } else if (item.name === "LIMIT_DEPTH") {
      // Limit verbs cap the limits, they can't raise them
      effectiveOpts.matchLimitRecursion = Math.min(
        effectiveOpts.matchLimitRecursion ?? Infinity,
        item.value,
      );
    } else if (item.name === "LIMIT_MATCH") {
      effectiveOpts.matchLimit = Math.min(
        effectiveOpts.matchLimit ?? Infinity,
        item.value,
      );
    } else if (item.name === "UTF" || item.name === "UTF8") {
      effectiveOpts.unicode = true;
    }
  }

  return effectiveOpts;
}

// Yields the leading start-option items of a parsed pattern.
export function* startOptions(ast) {
  if (ast.type !== "concatenation") return;

  for (const item of ast.items) {
    if (item.type !== "startOption") return;

    yield item;
  }
}
