#!/usr/bin/env elixir

# Script to derive each codepoint's script set from String.Tokenizer.tokenize/1, which does not
# expose it directly. The tokenizer rejects identifiers whose characters share no script, so a
# codepoint's script set is discovered by asking which anchors it will combine with: two codepoints
# tokenize together only when their script sets intersect.
#
# Output format: codepoint:anchor_signature
#   anchor_signature - "1"/"0" per anchor, in anchor order, or "-" when the codepoint can't appear
#                      in an identifier at all

output_file = Path.join(__DIR__, "scriptsets_elixir.txt")

# One representative codepoint per script likely to appear in identifiers.
anchors = [
  {?a, "Latin"},
  {0x03B1, "Greek"},
  {0x0430, "Cyrillic"},
  {0x05D0, "Hebrew"},
  {0x0627, "Arabic"},
  {0x0905, "Devanagari"},
  {0x4E00, "Han"},
  {0x3042, "Hiragana"},
  {0x30A2, "Katakana"},
  {0xAC00, "Hangul"},
  {0x0E01, "Thai"},
  # Mkhedruli - Asomtavruli (0x10A0) is Uncommon_Use, itself rejected by the tokenizer, and would
  # zero the Georgian bit for every codepoint.
  {0x10D0, "Georgian"},
  {0x0531, "Armenian"}
]

IO.puts("Anchors: #{Enum.map_join(anchors, ", ", fn {_cp, name} -> name end)}")

combines? = fn codepoint, anchor ->
  try do
    case String.Tokenizer.tokenize([anchor, codepoint]) do
      {_kind, _acc, [], _length, _ascii_only?, _special} -> "1"
      _rejected -> "0"
    end
  rescue
    _error -> "0"
  end
end

usable? = fn codepoint ->
  try do
    case String.Tokenizer.tokenize([?_, codepoint]) do
      {_kind, _acc, [], _length, _ascii_only?, _special} -> true
      _rejected -> false
    end
  rescue
    _error -> false
  end
end

output =
  0..0x10FFFF
  |> Enum.map_join("\n", fn codepoint ->
    signature =
      if usable?.(codepoint) do
        Enum.map_join(anchors, "", fn {anchor, _name} -> combines?.(codepoint, anchor) end)
      else
        "-"
      end

    "#{codepoint}:#{signature}"
  end)

File.write!(output_file, output)

IO.puts("Script sets written to #{output_file}")
