defmodule Hologram.DB.SortKeyTest do
  @moduledoc """
  IMPORTANT!
  Each test here has a related JavaScript test in test/javascript/sort_key_test.mjs, in the same
  order - the two tiers must compute the same keys, or a client sorts its own rows differently from
  the server. Always update both together, and the two implementations with them.
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

  test "version/0" do
    assert version() == 1
  end
end
