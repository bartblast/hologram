#!/usr/bin/env node

// Script to generate character to uppercase mapping using toUpperCase()
// Output format: codepoint:uppercased_codepoint(s) or codepoint:-

import fs from "fs";

import {fileURLToPath} from "url";
import {dirname} from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const outputFile = __dirname + "/mapping_javascript.txt";

// Generate mapping for all Unicode codepoints (0 to 0x10FFFF = 1,114,111)
const maxCodepoint = 0x10ffff;

console.log(
  `Generating uppercase mapping for codepoints 0 to ${maxCodepoint}...`,
);

const mapping = [];

for (let codepoint = 0; codepoint <= maxCodepoint; codepoint++) {
  try {
    const char = String.fromCodePoint(codepoint);
    const result = char.toUpperCase();
    const resultCodepoints = Array.from(result).map((c) => c.codePointAt(0));
    const resultStr = resultCodepoints.join(",");
    mapping.push(`${codepoint}:${resultStr}`);
  } catch {
    mapping.push(`${codepoint}:-`);
  }
}

fs.writeFileSync(outputFile, mapping.join("\n"));

console.log(`Mapping written to ${outputFile}`);
