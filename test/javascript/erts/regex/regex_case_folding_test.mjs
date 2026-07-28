"use strict";

import {assert, defineRuntimeGlobals} from "../../support/helpers.mjs";

import {caseVariants} from "../../../../assets/js/erts/regex/regex_case_folding.mjs";

defineRuntimeGlobals();

describe("caseVariants()", () => {
  it("returns the uppercase partner of a lowercase letter", () => {
    assert.deepEqual(caseVariants(0x61), [0x41]);
  });

  it("returns the lowercase partner of an uppercase letter", () => {
    assert.deepEqual(caseVariants(0x41), [0x61]);
  });

  it("returns the partner of a supplementary plane letter", () => {
    assert.deepEqual(caseVariants(0x10400), [0x10428]);
  });

  it("returns both other cases of a titlecase letter", () => {
    assert.deepEqual(caseVariants(0x01c5), [0x01c4, 0x01c6]);
  });

  it("returns the full set for each Kelvin sign set member", () => {
    assert.deepEqual(caseVariants(0x006b), [0x004b, 0x212a]);
    assert.deepEqual(caseVariants(0x004b), [0x006b, 0x212a]);
    assert.deepEqual(caseVariants(0x212a), [0x004b, 0x006b]);
  });

  it("returns the full set for each long s set member", () => {
    assert.deepEqual(caseVariants(0x0073), [0x0053, 0x017f]);
    assert.deepEqual(caseVariants(0x017f), [0x0053, 0x0073]);
  });

  it("returns the set members for micro sign, which lowercases to itself", () => {
    assert.deepEqual(caseVariants(0x00b5), [0x039c, 0x03bc]);
  });

  it("returns the set members for final sigma, which lowercases to itself", () => {
    assert.deepEqual(caseVariants(0x03c2), [0x03a3, 0x03c3]);
  });

  it("returns the four-member set for combining iota subscript", () => {
    assert.deepEqual(caseVariants(0x0345), [0x0399, 0x03b9, 0x1fbe]);
  });

  it("returns capital sharp s for sharp s, whose uppercase is two chars", () => {
    assert.deepEqual(caseVariants(0x00df), [0x1e9e]);
  });

  it("returns empty for dotless i, which folds only to itself", () => {
    assert.deepEqual(caseVariants(0x0131), []);
  });

  it("returns empty for capital I with dot, whose lowercase is two chars", () => {
    assert.deepEqual(caseVariants(0x0130), []);
  });

  it("returns empty for an uncased code point", () => {
    assert.deepEqual(caseVariants(0x35), []);
  });
});
