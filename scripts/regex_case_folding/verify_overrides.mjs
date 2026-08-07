#!/usr/bin/env node

// Script to verify the CASE_VARIANT_OVERRIDES table in
// assets/js/erts/regex/regex_case_folding.mjs. Re-derives the folding
// equivalence classes from the /iu oracle and asserts that caseVariants
// returns exactly the oracle variants for every code point.

import {caseVariants} from "../../assets/js/erts/regex/regex_case_folding.mjs";
import {buildTrueVariantsMap} from "./folding_oracle.mjs";

const MAX_CODE_POINT = 0x10ffff;

const trueVariantsMap = buildTrueVariantsMap();

const hex = (codePoint) => "0x" + codePoint.toString(16);

let mismatchCount = 0;

for (let codePoint = 0; codePoint <= MAX_CODE_POINT; codePoint++) {
  const actual = [...caseVariants(codePoint)].sort(
    (codePoint1, codePoint2) => codePoint1 - codePoint2,
  );

  const expected = trueVariantsMap.get(codePoint) ?? [];

  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    mismatchCount++;

    if (mismatchCount <= 10) {
      console.log(
        `MISMATCH ${hex(codePoint)}: module [${actual.map(hex).join(", ")}] vs oracle [${expected.map(hex).join(", ")}]`,
      );
    }
  }
}

if (mismatchCount === 0) {
  console.log("OK: caseVariants matches the oracle for all code points");
} else {
  console.log(`FAIL: ${mismatchCount} mismatches`);
  process.exit(1);
}
