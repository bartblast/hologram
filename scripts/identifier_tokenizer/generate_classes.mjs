#!/usr/bin/env node

// Script to generate the identifier classification of every Unicode codepoint using JavaScript's
// native Unicode support, in the same format as generate_classes.exs.
//
// The comparison (compare_classes.exs) shows the native properties CANNOT serve as the base the
// runtime derives from: Elixir restricts identifiers to codepoints typed Recommended or Inclusion
// in UTS 39's IdentifierType.txt, a property JavaScript regexes don't expose, leaving ~85k
// codepoints (2,489 ranges) that the closest native approximation accepts and the BEAM rejects.
// The runtime therefore carries the accept set itself, generated from classes_elixir.txt - this
// script and the comparison stay as the evidence for that decision, and to requantify the gap
// when either side upgrades its Unicode version.
//
// The predictor uses only native properties, no hand-carried tables:
//
//   start:
//     A-Z                                  -> alias (Elixir aliases are ASCII-uppercase-led)
//     _                                    -> identifier (not ID_Start, allowed by UAX31 profiles)
//     ID_Start and uppercase or titlecase  -> atom (uppercase non-ASCII, like Greek Omega)
//     ID_Start otherwise                   -> identifier
//     anything else                        -> error
//
//   continue: ID_Continue
//
// Both are additionally restricted to the UTS 39 recommended scripts, which Elixir's tokenizer
// applies as its security profile and which JavaScript expresses natively through the
// Script_Extensions property.
//
// Output format: codepoint:start:continue (identical to generate_classes.exs)

import fs from "fs";

import {fileURLToPath} from "url";
import {dirname} from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const outputFile = __dirname + "/classes_javascript.txt";

const maxCodepoint = 0x10ffff;

console.log(
  `Generating identifier classes for codepoints 0 to ${maxCodepoint}...`,
);

// UTS 39 Table 5 (recommended scripts), plus Common and Inherited.
const recommendedScripts = [
  "Zyyy",
  "Zinh",
  "Arab",
  "Armn",
  "Beng",
  "Bopo",
  "Cyrl",
  "Deva",
  "Ethi",
  "Geor",
  "Grek",
  "Gujr",
  "Guru",
  "Hang",
  "Hani",
  "Hebr",
  "Hira",
  "Kana",
  "Khmr",
  "Knda",
  "Laoo",
  "Latn",
  "Mlym",
  "Mymr",
  "Orya",
  "Sinh",
  "Taml",
  "Telu",
  "Thaa",
  "Thai",
  "Tibt",
];

const recommendedRegex = new RegExp(
  `^[${recommendedScripts.map((script) => `\\p{scx=${script}}`).join("")}]$`,
  "u",
);

const idStartRegex = /^\p{ID_Start}$/u;
const idContinueRegex = /^\p{ID_Continue}$/u;
const upperRegex = /^[\p{Lu}\p{Lt}]$/u;

const startClass = (codepoint, char) => {
  if (codepoint >= 65 && codepoint <= 90) {
    return "alias";
  }

  if (codepoint === 95) {
    return "identifier";
  }

  if (idStartRegex.test(char) && recommendedRegex.test(char)) {
    return upperRegex.test(char) ? "atom" : "identifier";
  }

  return "error";
};

const lines = [];

for (let codepoint = 0; codepoint <= maxCodepoint; codepoint++) {
  const char = String.fromCodePoint(codepoint);
  const start = startClass(codepoint, char);

  const continues =
    idContinueRegex.test(char) && recommendedRegex.test(char) ? "1" : "0";

  lines.push(`${codepoint}:${start}:${continues}`);
}

fs.writeFileSync(outputFile, lines.join("\n"));

console.log(`Classes written to ${outputFile}`);
