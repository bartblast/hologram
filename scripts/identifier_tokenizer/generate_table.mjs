#!/usr/bin/env node

// Script to generate assets/js/elixir/string/tokenizer/identifier_data.mjs from
// classes_elixir.txt - the BEAM's identifier classification of every Unicode codepoint, carried
// by the runtime because no native JavaScript property can express it (see generate_classes.mjs).
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
// After writing the module, the script imports it back and checks the classification of every
// codepoint against classes_elixir.txt, so a generation bug cannot survive silently.

import fs from "fs";
import zlib from "zlib";

import {fileURLToPath} from "url";
import {dirname} from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));

const sourceFile = __dirname + "/classes_elixir.txt";

const outputFile =
  __dirname + "/../../assets/js/elixir/string/tokenizer/identifier_data.mjs";

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

const moduleSource = `"use strict";

// GENERATED FILE - do not edit. Regenerate with:
//   node scripts/identifier_tokenizer/generate_table.mjs
//
// The BEAM's identifier classification of every Unicode codepoint, from UTS 39's
// IdentifierType.txt as Elixir's String.Tokenizer applies it. Carried as data because no native
// JavaScript property expresses it. See scripts/identifier_tokenizer/ for the derivation and the
// comparison against the closest native approximation.
//
// Encoding: base36 delta string - per range, gap-from-previous-range-end "." length, then the
// range's class letter: I identifier start, A atom start, L alias start, C continues only. All
// four classes may continue an identifier. RANGE_STARTS/RANGE_ENDS are sorted for binary search.

const ENCODED_RANGES =
  "${encoded}";

const rangeCount = (ENCODED_RANGES.match(/[IALC]/g) ?? []).length;

const RANGE_STARTS = new Uint32Array(rangeCount);
const RANGE_ENDS = new Uint32Array(rangeCount);
const RANGE_CLASSES = new Array(rangeCount);

{
  const tokenRegex = /([0-9a-z]+)\\.([0-9a-z]*)([IALC])/g;
  let index = 0;
  let previousEnd = 0;
  let match;

  while ((match = tokenRegex.exec(ENCODED_RANGES)) !== null) {
    const start = previousEnd + parseInt(match[1], 36);
    const end = start + (match[2] === "" ? 0 : parseInt(match[2], 36));

    RANGE_STARTS[index] = start;
    RANGE_ENDS[index] = end;
    RANGE_CLASSES[index] = match[3];

    previousEnd = end;
    ++index;
  }
}

export {RANGE_CLASSES, RANGE_ENDS, RANGE_STARTS};
`;

fs.writeFileSync(outputFile, moduleSource);

const gzipped = zlib.gzipSync(moduleSource, {level: 9}).length;

console.log(
  `Written ${outputFile}: ${moduleSource.length} bytes raw, ${gzipped} gzipped`,
);

// Verification: import the emitted module and check every codepoint against the source data.
console.log("Verifying against the oracle...");

const {RANGE_CLASSES, RANGE_ENDS, RANGE_STARTS} = await import(outputFile);

const lookup = (codepoint) => {
  let low = 0;
  let high = RANGE_STARTS.length - 1;

  while (low <= high) {
    const middle = (low + high) >> 1;

    if (codepoint < RANGE_STARTS[middle]) {
      high = middle - 1;
    } else if (codepoint > RANGE_ENDS[middle]) {
      low = middle + 1;
    } else {
      return RANGE_CLASSES[middle];
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
