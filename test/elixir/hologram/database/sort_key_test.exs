defmodule Hologram.Database.SortKeyTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Database.SortKey

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
