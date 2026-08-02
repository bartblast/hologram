"use strict";

// Shared oracle for the regex case folding scripts. Groups all code points
// into Unicode simple case folding equivalence classes: candidate classes
// come from connecting each code point to its toLowerCase/toUpperCase
// mappings, then each candidate class is split into true folding classes
// with the JS /iu canonicalizer as the oracle.

const MAX_CODE_POINT = 0x10ffff;

// Returns a Map from every cased code point to the sorted list of the other
// members of its folding equivalence class.
export function buildTrueVariantsMap() {
  // Union-find over toLowerCase/toUpperCase edges gives candidate classes
  const parent = new Map();

  const find = (codePoint) => {
    while (parent.get(codePoint) !== codePoint) {
      parent.set(codePoint, parent.get(parent.get(codePoint)));
      codePoint = parent.get(codePoint);
    }

    return codePoint;
  };

  const union = (codePoint1, codePoint2) => {
    if (!parent.has(codePoint1)) parent.set(codePoint1, codePoint1);
    if (!parent.has(codePoint2)) parent.set(codePoint2, codePoint2);

    const root1 = find(codePoint1);
    const root2 = find(codePoint2);

    if (root1 !== root2) parent.set(root1, root2);
  };

  for (let codePoint = 0; codePoint <= MAX_CODE_POINT; codePoint++) {
    for (const variant of naiveVariants(codePoint)) union(codePoint, variant);
  }

  const candidateClasses = new Map();

  for (const codePoint of parent.keys()) {
    const root = find(codePoint);

    if (!candidateClasses.has(root)) candidateClasses.set(root, []);

    candidateClasses.get(root).push(codePoint);
  }

  // Split candidate classes into true folding classes with the oracle,
  // severing edges like dotless i -> I, which is reachable through
  // toUpperCase but folds only to itself
  const trueVariantsMap = new Map();

  for (const members of candidateClasses.values()) {
    members.sort((codePoint1, codePoint2) => codePoint1 - codePoint2);

    const foldingClasses = [];

    for (const codePoint of members) {
      const matched = foldingClasses.find((foldingClass) =>
        foldEqual(foldingClass[0], codePoint),
      );

      if (matched !== undefined) {
        matched.push(codePoint);
      } else {
        foldingClasses.push([codePoint]);
      }
    }

    for (const foldingClass of foldingClasses) {
      for (const codePoint of foldingClass) {
        trueVariantsMap.set(
          codePoint,
          foldingClass.filter((member) => member !== codePoint),
        );
      }
    }
  }

  return trueVariantsMap;
}

// True iff the two code points match caselessly under JS /iu semantics,
// which canonicalizes through Unicode simple case folding.
function foldEqual(codePoint1, codePoint2) {
  const regex = new RegExp(`^\\u{${codePoint1.toString(16)}}$`, "iu");

  return regex.test(String.fromCodePoint(codePoint2));
}

// Returns {toLowerCase, toUpperCase} minus self, single code points only.
export function naiveVariants(codePoint) {
  const char = String.fromCodePoint(codePoint);
  const variants = new Set();

  for (const mapped of [char.toLowerCase(), char.toUpperCase()]) {
    const mappedCodePoint = singleCodePoint(mapped);

    if (mappedCodePoint !== null && mappedCodePoint !== codePoint) {
      variants.add(mappedCodePoint);
    }
  }

  return variants;
}

function singleCodePoint(str) {
  return str.length === String.fromCodePoint(str.codePointAt(0)).length
    ? str.codePointAt(0)
    : null;
}
