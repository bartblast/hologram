"use strict";

import {assert} from "./support/helpers.mjs";

import SortKey from "../../assets/js/sort_key.mjs";

// Mirrors test/elixir/hologram/db/sort_key_test.exs - the Elixir module is the reference
// implementation, and the two suites carry the same cases in the same order.
describe("SortKey", () => {
  describe("compute()", () => {
    const compute = SortKey.compute;

    it("caps a multibyte key without splitting the boundary codepoint", () => {
      const value = "a".repeat(63) + "ωω";

      assert.equal(compute(value), "a".repeat(63));
    });

    it("caps the key at 64 bytes", () => {
      const value = "a".repeat(70);

      assert.equal(compute(value), "a".repeat(64));
    });

    it("computes an empty key from an empty string", () => {
      assert.equal(compute(""), "");
    });

    it("downcases the value", () => {
      assert.equal(compute("Apple"), "apple");
    });

    it("folds non-decomposable letters", () => {
      assert.equal(compute("straße"), "strasse");
      assert.equal(compute("Łukasz"), "lukasz");
      assert.equal(compute("Œuvre"), "oeuvre");
    });

    it("keeps cjk characters unchanged", () => {
      assert.equal(compute("中文"), "中文");
    });

    it("keeps indic vowel signs unchanged", () => {
      assert.equal(compute("कि"), "कि");
    });

    it("strips arabic vowel marks", () => {
      assert.equal(compute("كَتَبَ"), "كتب");
    });

    it("strips hebrew vowel points", () => {
      assert.equal(compute("שָׁלוֹם"), "שׁלום");
      assert.equal(compute("כׇל"), "כל");
    });

    it("strips diacritics via canonical decomposition", () => {
      assert.equal(compute("Zürich"), "zurich");
      assert.equal(compute("Łódź"), "lodz");
      assert.equal(compute("café"), "cafe");
    });
  });

  it("version()", () => {
    assert.equal(SortKey.version(), 1);
  });
});
