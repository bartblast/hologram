#!/usr/bin/env node

// Script to generate the OVERRIDE_FOLDING_CLASSES table in
// assets/js/erts/regex/regex_case_folding.mjs.
//
// Naive variants of a code point = {toLowerCase, toUpperCase} minus self
// (single code point results only). True variants = the other members of its
// Unicode simple case folding equivalence class, which is what JS RegExp /iu
// canonicalization uses. This script finds every folding class in which some
// member's naive variants differ from its true variants, using /iu itself as
// the folding oracle, and prints the class entries to paste into the module.

import {buildTrueVariantsMap, naiveVariants} from "./folding_oracle.mjs";

const MAX_CODE_POINT = 0x10ffff;

const trueVariantsMap = buildTrueVariantsMap();

const hex = (codePoint) => "0x" + codePoint.toString(16).padStart(4, "0");

const show = (codePoint) => String.fromCodePoint(codePoint);

const overrideClasses = [];
const seen = new Set();

for (let codePoint = 0; codePoint <= MAX_CODE_POINT; codePoint++) {
  if (seen.has(codePoint)) continue;

  const trueVariants = trueVariantsMap.get(codePoint) ?? [];
  const naive = naiveVariants(codePoint);

  const missing = trueVariants.filter((variant) => !naive.has(variant));
  const extra = [...naive].filter((variant) => !trueVariants.includes(variant));

  if (missing.length === 0 && extra.length === 0) continue;

  const foldingClass = [codePoint, ...trueVariants].sort(
    (codePoint1, codePoint2) => codePoint1 - codePoint2,
  );

  for (const member of foldingClass) seen.add(member);

  overrideClasses.push(foldingClass);
}

for (const foldingClass of overrideClasses) {
  console.log(
    `  [${foldingClass.map(hex).join(", ")}], // ${foldingClass.map(show).join(" ")}`,
  );
}

console.error(`Override classes: ${overrideClasses.length}`);
