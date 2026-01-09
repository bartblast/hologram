#!/usr/bin/env node

// Script to generate character to uppercase mapping using toUpperCase()
// Output format: codepoint:uppercased_codepoint(s) or codepoint:-

import fs from "fs";

import {fileURLToPath} from "url";
import {dirname} from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const outputFile = __dirname + "/upcase_mapping_javascript.txt";

// Generate mappings for all Unicode codepoints (0 to 0x10FFFF = 1,114,111)
const maxCodepoint = 0x10ffff;

console.log(`Generating upcase mapping for codepoints 0 to ${maxCodepoint}...`);

const mappings = [];

for (let codepoint = 0; codepoint <= maxCodepoint; codepoint++) {
  try {
    const char = String.fromCodePoint(codepoint);
    const result = char.toUpperCase();
    const resultCodepoints = Array.from(result).map((c) => c.codePointAt(0));
    const resultStr = resultCodepoints.join(",");
    mappings.push(`${codepoint}:${resultStr}`);
  } catch (_error) {
    mappings.push(`${codepoint}:-`);
  }
}

fs.writeFileSync(outputFile, mappings.join("\n"));

console.log(`Mapping written to ${outputFile}`);
