"use strict";

import {assert, defineRuntimeGlobals} from "../../support/helpers.mjs";

import {
  isCompoundUnicodeProperty,
  unicodePropertyAtoms,
} from "../../../../assets/js/erts/regex/regex_unicode_properties.mjs";

defineRuntimeGlobals();

describe("isCompoundUnicodeProperty()", () => {
  it("returns true for a special name with more than one atom", () => {
    assert.isTrue(isCompoundUnicodeProperty("Xan"));
  });

  it("returns true for every other compound special name", () => {
    assert.isTrue(isCompoundUnicodeProperty("Xps"));
    assert.isTrue(isCompoundUnicodeProperty("Xsp"));
    assert.isTrue(isCompoundUnicodeProperty("Xuc"));
    assert.isTrue(isCompoundUnicodeProperty("Xwd"));
  });

  it("returns false for a category", () => {
    assert.isFalse(isCompoundUnicodeProperty("L"));
  });

  it("returns false for an unknown name", () => {
    assert.isFalse(isCompoundUnicodeProperty("Foo"));
  });
});

describe("unicodePropertyAtoms()", () => {
  it("returns a category escape", () => {
    assert.deepEqual(unicodePropertyAtoms("L", false), ["\\p{L}"]);
  });

  it("returns a binary property escape", () => {
    assert.deepEqual(unicodePropertyAtoms("Alphabetic", false), [
      "\\p{Alphabetic}",
    ]);
  });

  it("returns the Any escape", () => {
    assert.deepEqual(unicodePropertyAtoms("Any", false), ["\\p{Any}"]);
  });

  it("matches a bare script name as a script extension", () => {
    assert.deepEqual(unicodePropertyAtoms("Greek", false), [
      "\\p{Script_Extensions=Greek}",
    ]);
  });

  it("keeps a name=value property", () => {
    assert.deepEqual(unicodePropertyAtoms("sc=Greek", false), [
      "\\p{sc=Greek}",
    ]);
  });

  it("matches a bare Inherited name by script", () => {
    assert.deepEqual(unicodePropertyAtoms("Inherited", false), [
      "\\p{Script=Inherited}",
    ]);
  });

  it("matches a Common script alias by script", () => {
    assert.deepEqual(unicodePropertyAtoms("Zyyy", false), ["\\p{Script=Zyyy}"]);
  });

  it("matches an Inherited script alias by script", () => {
    assert.deepEqual(unicodePropertyAtoms("Zinh", false), ["\\p{Script=Zinh}"]);
  });

  it("matches the Qaai Inherited script alias by script", () => {
    assert.deepEqual(unicodePropertyAtoms("Qaai", false), ["\\p{Script=Qaai}"]);
  });

  it("matches a Common script by script under the sc key", () => {
    assert.deepEqual(unicodePropertyAtoms("sc=Common", false), [
      "\\p{Script=Common}",
    ]);
  });

  it("matches a Common script by script under the Script key", () => {
    assert.deepEqual(unicodePropertyAtoms("Script=Common", false), [
      "\\p{Script=Common}",
    ]);
  });

  it("matches a Common script by script under the Script_Extensions key", () => {
    assert.deepEqual(unicodePropertyAtoms("Script_Extensions=Common", false), [
      "\\p{Script=Common}",
    ]);
  });

  it("matches a bare Common name by script", () => {
    assert.deepEqual(unicodePropertyAtoms("Common", false), [
      "\\p{Script=Common}",
    ]);
  });

  it("matches a Common script extension by script", () => {
    assert.deepEqual(unicodePropertyAtoms("scx=Common", false), [
      "\\p{Script=Common}",
    ]);
  });

  it("returns the Lu escape without caseless", () => {
    assert.deepEqual(unicodePropertyAtoms("Lu", false), ["\\p{Lu}"]);
  });

  it("widens Lu to cased letters under caseless", () => {
    assert.deepEqual(unicodePropertyAtoms("Lu", true), ["\\p{LC}"]);
  });

  it("widens Ll to cased letters under caseless", () => {
    assert.deepEqual(unicodePropertyAtoms("Ll", true), ["\\p{LC}"]);
  });

  it("widens Lt to cased letters under caseless", () => {
    assert.deepEqual(unicodePropertyAtoms("Lt", true), ["\\p{LC}"]);
  });

  it("keeps other categories under caseless", () => {
    assert.deepEqual(unicodePropertyAtoms("Mn", true), ["\\p{Mn}"]);
  });

  it("returns the Xan atoms", () => {
    assert.deepEqual(unicodePropertyAtoms("Xan", false), ["\\p{L}", "\\p{N}"]);
  });

  it("returns the Xps atoms", () => {
    assert.deepEqual(unicodePropertyAtoms("Xps", false), [
      "\\p{White_Space}",
      "\\u180e",
    ]);
  });

  it("returns the Xsp atoms", () => {
    assert.deepEqual(unicodePropertyAtoms("Xsp", false), [
      "\\p{White_Space}",
      "\\u180e",
    ]);
  });

  it("returns the Xuc atoms", () => {
    assert.deepEqual(unicodePropertyAtoms("Xuc", false), [
      "$",
      "@",
      "`",
      "\\u{a0}-\\u{d7ff}",
      "\\u{e000}-\\u{10ffff}",
    ]);
  });

  it("returns the Xwd atoms", () => {
    assert.deepEqual(unicodePropertyAtoms("Xwd", false), [
      "\\p{L}",
      "\\p{N}",
      "\\p{Mn}",
      "\\p{Pc}",
    ]);
  });

  it("raises on a script-only name followed by another value", () => {
    assert.throws(
      () => unicodePropertyAtoms("sc=Common=x", false),
      Error,
      "unsupported Unicode property: sc=Common=x",
    );
  });

  it("raises on an unknown name", () => {
    assert.throws(
      () => unicodePropertyAtoms("Foo", false),
      Error,
      "unsupported Unicode property: Foo",
    );
  });
});
