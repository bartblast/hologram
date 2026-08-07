#!/usr/bin/env node

// Script to predict each codepoint's anchor signature (see generate_scriptsets.exs) from
// JavaScript's native Script_Extensions property, applying the UTS 39 augmentation rules the
// BEAM's mixed-script detection uses:
//
//   Hani -> Hanb, Jpan, Kore     Hira, Kana -> Jpan     Hang -> Kore     Bopo -> Hanb
//
// A codepoint combines with an anchor when their augmented script sets intersect. Jpan, Kore and
// Hanb are pseudo-scripts regexes can't query, so membership is derived from the base scripts
// that imply them. Codepoints whose extensions are only Common or Inherited carry an empty
// script set, which combines with everything.
//
// Signatures are emitted for every codepoint - the comparison (compare_scriptsets.exs) skips the
// ones the BEAM marks unusable, since they never reach a script-set check.
//
// Output format: codepoint:anchor_signature (anchors as in generate_scriptsets.exs)

import fs from "fs";

import {fileURLToPath} from "url";
import {dirname} from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const outputFile = __dirname + "/scriptsets_javascript.txt";

const maxCodepoint = 0x10ffff;

console.log(
  `Generating script signatures for codepoints 0 to ${maxCodepoint}...`,
);

// Anchor order must match generate_scriptsets.exs.
const anchorSets = [
  ["Latn"], // Latin
  ["Grek"], // Greek
  ["Cyrl"], // Cyrillic
  ["Hebr"], // Hebrew
  ["Arab"], // Arabic
  ["Deva"], // Devanagari
  ["Hani", "Hanb", "Jpan", "Kore"], // Han
  ["Hira", "Jpan"], // Hiragana
  ["Kana", "Jpan"], // Katakana
  ["Hang", "Kore"], // Hangul
  ["Thai"], // Thai
  ["Geor"], // Georgian
  ["Armn"], // Armenian
];

const baseScripts = [
  "Latn",
  "Grek",
  "Cyrl",
  "Hebr",
  "Arab",
  "Deva",
  "Hani",
  "Hira",
  "Kana",
  "Hang",
  "Bopo",
  "Thai",
  "Geor",
  "Armn",
];

const scriptRegexes = new Map(
  baseScripts.map((script) => [
    script,
    new RegExp(`^\\p{scx=${script}}$`, "u"),
  ]),
);

const commonRegex = /^[\p{scx=Zyyy}\p{scx=Zinh}]$/u;

const augmentedScripts = (char) => {
  const scripts = new Set(
    baseScripts.filter((script) => scriptRegexes.get(script).test(char)),
  );

  if (scripts.has("Hani") || scripts.has("Hira") || scripts.has("Kana")) {
    scripts.add("Jpan");
  }

  if (scripts.has("Hani") || scripts.has("Hang")) {
    scripts.add("Kore");
  }

  if (scripts.has("Hani") || scripts.has("Bopo")) {
    scripts.add("Hanb");
  }

  return scripts;
};

const lines = [];

for (let codepoint = 0; codepoint <= maxCodepoint; codepoint++) {
  const char = String.fromCodePoint(codepoint);

  let signature;

  if (commonRegex.test(char)) {
    signature = "1".repeat(anchorSets.length);
  } else {
    const scripts = augmentedScripts(char);

    signature = anchorSets
      .map((anchorSet) =>
        anchorSet.some((script) => scripts.has(script)) ? "1" : "0",
      )
      .join("");
  }

  lines.push(`${codepoint}:${signature}`);
}

fs.writeFileSync(outputFile, lines.join("\n"));

console.log(`Script signatures written to ${outputFile}`);
