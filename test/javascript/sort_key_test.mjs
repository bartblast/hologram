"use strict";

import {assert} from "./support/helpers.mjs";

import SortKey from "../../assets/js/sort_key.mjs";

// IMPORTANT!
// Each test here has a related Elixir test in test/elixir/hologram/db/sort_key_test.exs, in the
// same order - the two tiers must compute the same keys, or a client sorts its own rows differently
// from the server. Always update both together, and the two implementations with them. The Elixir
// module is the reference implementation.
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

    // One letter with two lowercase spellings, so a dictionary puts them together - and the two
    // tiers spell it differently on the way in, since only JavaScript applies Unicode's
    // Final_Sigma mapping. Folding answers both at once.
    it("folds the two spellings of greek lowercase sigma together", () => {
      assert.equal(compute("ΑΘΗΝΑΣ"), "αθηνασ");
      assert.equal(compute("αθηνας"), "αθηνασ");
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
