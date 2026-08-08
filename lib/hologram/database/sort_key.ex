defmodule Hologram.Database.SortKey do
  @moduledoc false

  # Computes practical-order sort keys for string attribute values - the derived
  # values that `order_by` companion columns store and both tiers compare. The
  # rule set is versioned: keys are always recomputable from source values, so a
  # version bump regenerates them (server-side by the reconciler, client-side
  # from local rows) without migrations or wire cost.

  # Version 1 rules: Unicode downcase, canonical decomposition (NFD), combining
  # marks stripped in the pinned ranges below, non-decomposable letters folded
  # through the pinned map, and the key capped at a byte-size prefix. Ordering
  # ties past the cap are broken by the full original value and id downstream -
  # the cap is a storage lever, never a correctness lever.

  # The pinned strip ranges cover marks that dictionaries ignore: general
  # combining diacritics, Hebrew niqqud, and Arabic harakat. Indic vowel signs
  # stay deliberately unstripped - they distinguish words.
  @combining_mark_ranges [
    0x0300..0x036F,
    0x05B0..0x05BC,
    0x05C7..0x05C7,
    0x064B..0x065F,
    0x0670..0x0670,
    0x1AB0..0x1AFF,
    0x1DC0..0x1DFF,
    0x20D0..0x20FF,
    0xFE20..0xFE2F
  ]

  # Letters NFD cannot decompose, folded to their dictionary neighbors.
  @fold_map %{
    "ß" => "ss",
    "æ" => "ae",
    "đ" => "d",
    "ħ" => "h",
    "ı" => "i",
    "ĸ" => "k",
    "ł" => "l",
    "ŋ" => "n",
    "œ" => "oe",
    "ð" => "d",
    "ø" => "o",
    "þ" => "th",
    "ſ" => "s"
  }

  @max_key_bytes 64

  @doc """
  Computes the sort key of the given string value - downcased, canonically
  decomposed, with ignorable combining marks stripped and non-decomposable
  letters folded, capped at a byte-size prefix that never splits a codepoint.
  """
  @spec compute(String.t()) :: String.t()
  def compute(value) do
    value
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> strip_combining_marks()
    |> fold_letters()
    |> cap()
  end

  @doc """
  Returns the version of the sort-key rule set.
  """
  # TODO: reconciliation bookkeeps this version in hologram_system and
  # regenerates stale companions on a mismatch (clients regenerate their stored
  # keys the same way) - the version must not bump before that wiring exists,
  # or existing rows would keep keys computed under the old rules.
  @spec version() :: pos_integer
  def version, do: 1

  defp cap(text) when byte_size(text) <= @max_key_bytes, do: text

  defp cap(text), do: take_codepoint_prefix(text, "", @max_key_bytes)

  defp combining_mark?(codepoint) do
    Enum.any?(@combining_mark_ranges, fn range -> codepoint in range end)
  end

  defp fold_letters(text) do
    for <<codepoint::utf8 <- text>>, into: "" do
      Map.get(@fold_map, <<codepoint::utf8>>, <<codepoint::utf8>>)
    end
  end

  defp strip_combining_marks(text) do
    for <<codepoint::utf8 <- text>>, not combining_mark?(codepoint), into: "" do
      <<codepoint::utf8>>
    end
  end

  defp take_codepoint_prefix(<<codepoint::utf8, rest::binary>>, acc, budget) do
    appended = acc <> <<codepoint::utf8>>

    if byte_size(appended) > budget do
      acc
    else
      take_codepoint_prefix(rest, appended, budget)
    end
  end

  defp take_codepoint_prefix(<<>>, acc, _budget), do: acc
end
