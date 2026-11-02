defmodule Hologram.DB.SortKeyTest do
  @moduledoc """
  IMPORTANT!
  Each test here has a related JavaScript test in test/javascript/sort_key_test.mjs, in the same
  order - the two tiers must compute the same keys, or a client sorts its own rows differently from
  the server. Always update both together, and the two implementations with them. The search_key/1
  tests have no twin: only the server stores a search key, and the browser folds when it searches.
  """
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.SortKey

  describe "compute/1" do
    test "caps a multibyte key without splitting the boundary codepoint" do
      value = String.duplicate("a", 63) <> "ωω"

      assert compute(value) == String.duplicate("a", 63)
    end

    test "caps the key at 64 bytes" do
      value = String.duplicate("a", 70)

      assert compute(value) == String.duplicate("a", 64)
    end

    test "computes an empty key from an empty string" do
      assert compute("") == ""
    end

    test "downcases the value" do
      assert compute("Apple") == "apple"
    end

    test "folds non-decomposable letters" do
      assert compute("straße") == "strasse"
      assert compute("Łukasz") == "lukasz"
      assert compute("Œuvre") == "oeuvre"
    end

    # One letter with two lowercase spellings, so a dictionary puts them together - and the two
    # tiers spell it differently on the way in, since only JavaScript applies Unicode's
    # Final_Sigma mapping. Folding answers both at once.
    test "folds the two spellings of greek lowercase sigma together" do
      assert compute("ΑΘΗΝΑΣ") == "αθηνασ"
      assert compute("αθηνας") == "αθηνασ"
    end

    test "keeps cjk characters unchanged" do
      assert compute("中文") == "中文"
    end

    test "keeps indic vowel signs unchanged" do
      assert compute("कि") == "कि"
    end

    test "strips arabic vowel marks" do
      assert compute("كَتَبَ") == "كتب"
    end

    test "strips hebrew vowel points" do
      assert compute("שָׁלוֹם") == "שׁלום"
      assert compute("כׇל") == "כל"
    end

    test "strips diacritics via canonical decomposition" do
      assert compute("Zürich") == "zurich"
      assert compute("Łódź") == "lodz"
      assert compute("café") == "cafe"
    end
  end

  describe "fold/1" do
    test "folds the value the way its sort key is folded" do
      assert fold("Łódź Zürich") == "lodz zurich"
    end

    test "keeps the whole folded value past the sort key's cap" do
      value = String.duplicate("A", 70)

      assert fold(value) == String.duplicate("a", 70)
    end

    # A Hangul syllable decomposes into its two or three jamo, so the folded form is longer.
    test "decomposes a hangul syllable into its jamo" do
      assert fold("한") == "\u1112\u1161\u11AB"
    end
  end

  describe "search_key/1" do
    test "is nil for a value whose folded form fits the sort key" do
      assert search_key(String.duplicate("A", 64)) == nil
    end

    test "is the whole folded value when it is longer than the sort key keeps" do
      value = String.duplicate("A", 65)

      assert search_key(value) == String.duplicate("a", 65)
    end

    # 8 syllables are 24 bytes, and their 24 jamo 72 - past the sort key's 64.
    test "is the folded value of a short value that folds past the sort key's cap" do
      value = String.duplicate("한", 8)

      assert search_key(value) == String.duplicate("\u1112\u1161\u11AB", 8)
    end
  end

  test "version/0" do
    assert version() == 1
  end
end
