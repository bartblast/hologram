#!/usr/bin/env node

// Script to regenerate the identifier class table inside
// assets/js/elixir/string/tokenizer.mjs (the GENERATED RANGES section) from classes_elixir.txt -
// the BEAM's identifier classification of every Unicode codepoint, carried by the runtime because
// no native JavaScript property can express it (see generate_classes.mjs).
//
// Codepoints outside the table are unusable in identifiers. The ones inside carry one of four
// combined classes:
//
//   I - identifier start, continues        (lowercase starters, Han, etc.)
//   A - atom start, continues              (uppercase non-ASCII, like Greek Omega)
//   L - alias start, continues             (A-Z)
//   C - continues only                     (digits, combining marks, _? -like enders)
//
// Contiguous codepoints sharing a class collapse into ranges, encoded as a base36 delta string:
// each range is gap-from-previous-range-end "." length, followed by its uppercase class letter.
// Class letters can't collide with the number tokens, which base36 keeps lowercase.
//
// After splicing, the script decodes the encoded string back (the same way the module does) and
// checks the classification of every codepoint against classes_elixir.txt, so a generation bug
// cannot survive silently.

import fs from "fs";

import {fileURLToPath} from "url";
import {dirname} from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));

const sourceFile = __dirname + "/classes_elixir.txt";
const moduleFile = __dirname + "/../../assets/js/elixir/string/tokenizer.mjs";

const startMarker =
  "// GENERATED RANGES START - regenerate with: node scripts/identifier_tokenizer/generate_table.mjs";

const endMarker = "// GENERATED RANGES END";

// start class + continue flag -> class letter
const classLetter = (start, continues) => {
  if (start === "identifier" && continues === "1") return "I";
  if (start === "atom" && continues === "1") return "A";
  if (start === "alias" && continues === "1") return "L";
  if (start === "error" && continues === "1") return "C";
  if (start === "error" && continues === "0") return null;

  throw new Error(`unexpected class: ${start}:${continues}`);
};

console.log(`Reading ${sourceFile}...`);

const classes = [];

for (const line of fs.readFileSync(sourceFile, "utf8").split("\n")) {
  const [codepoint, start, continues] = line.split(":");
  classes[Number(codepoint)] = classLetter(start, continues);
}

const ranges = [];

for (let codepoint = 0; codepoint < classes.length; codepoint++) {
  const letter = classes[codepoint];

  if (letter === null) {
    continue;
  }

  const last = ranges[ranges.length - 1];

  if (last && last.letter === letter && codepoint === last.end + 1) {
    last.end = codepoint;
  } else {
    ranges.push({start: codepoint, end: codepoint, letter});
  }
}

console.log(`Ranges: ${ranges.length}`);

let encoded = "";
let previousEnd = 0;

for (const {start, end, letter} of ranges) {
  const gap = start - previousEnd;
  const length = end - start;
  encoded += `${gap.toString(36)}.${length.toString(36)}${letter}`;
  previousEnd = end;
}

const moduleSource = fs.readFileSync(moduleFile, "utf8");
const startIndex = moduleSource.indexOf(startMarker);
const endIndex = moduleSource.indexOf(endMarker);

if (startIndex === -1 || endIndex === -1) {
  console.log(`FAIL: markers not found in ${moduleFile}`);
  process.exit(1);
}

const generatedSection = `${startMarker}
const ENCODED_RANGES =
  "${encoded}";
`;

const updatedSource =
  moduleSource.slice(0, startIndex) +
  generatedSection +
  moduleSource.slice(endIndex);

fs.writeFileSync(moduleFile, updatedSource);

console.log(`Updated ${moduleFile} (${encoded.length} chars encoded)`);

// Verification: decode the encoded string the way the module does, and check every codepoint
// against the source data.
console.log("Verifying against the oracle...");

const rangeStarts = [];
const rangeEnds = [];
const rangeClasses = [];

{
  const tokenRegex = /([0-9a-z]+)\.([0-9a-z]*)([IALC])/g;
  let decodedEnd = 0;
  let match;

  while ((match = tokenRegex.exec(encoded)) !== null) {
    const start = decodedEnd + parseInt(match[1], 36);
    const end = start + (match[2] === "" ? 0 : parseInt(match[2], 36));

    rangeStarts.push(start);
    rangeEnds.push(end);
    rangeClasses.push(match[3]);

    decodedEnd = end;
  }
}

const lookup = (codepoint) => {
  let low = 0;
  let high = rangeStarts.length - 1;

  while (low <= high) {
    const middle = (low + high) >> 1;

    if (codepoint < rangeStarts[middle]) {
      high = middle - 1;
    } else if (codepoint > rangeEnds[middle]) {
      low = middle + 1;
    } else {
      return rangeClasses[middle];
    }
  }

  return null;
};

let mismatchCount = 0;

for (let codepoint = 0; codepoint < classes.length; codepoint++) {
  if (lookup(codepoint) !== classes[codepoint]) {
    mismatchCount++;

    if (mismatchCount <= 10) {
      console.log(
        `MISMATCH ${codepoint}: table ${lookup(codepoint)} vs oracle ${classes[codepoint]}`,
      );
    }
  }
}

if (mismatchCount === 0) {
  console.log("OK: table matches the oracle for all codepoints");
} else {
  console.log(`FAIL: ${mismatchCount} mismatches`);
  process.exit(1);
}
