#!/usr/bin/env elixir

# Script to generate the identifier classification of every Unicode codepoint using
# String.Tokenizer.tokenize/1, which is what Macro.classify_atom/1 consults to decide whether an
# atom needs quoting.
#
# Two questions are asked per codepoint, because a character can be allowed to continue an
# identifier without being allowed to start one:
#
#   * start    - what tokenizing the codepoint on its own yields
#   * continue - whether tokenizing "_" followed by the codepoint consumes both
#
# The continue probe is prefixed with "_" rather than a letter because the tokenizer rejects
# mixed-script identifiers: a Latin prefix would report every non-Latin codepoint as unable to
# continue, when what it cannot do is share an identifier with Latin. "_" is Common script, which
# combines with every other script.
#
# Output format: codepoint:start:continue
#   start    - identifier | alias | atom | error (anything the tokenizer rejects)
#   continue - 1 when the codepoint continues an identifier, 0 otherwise

output_file = Path.join(__DIR__, "classes_elixir.txt")

max_codepoint = 0x10FFFF

IO.puts("Generating identifier classes for codepoints 0 to #{max_codepoint}...")

start_class = fn codepoint ->
  try do
    case String.Tokenizer.tokenize([codepoint]) do
      {kind, _acc, [], _length, _ascii_only?, _special} -> Atom.to_string(kind)
      _rejected -> "error"
    end
  rescue
    _error -> "error"
  end
end

continues? = fn codepoint ->
  try do
    case String.Tokenizer.tokenize([?_, codepoint]) do
      {_kind, _acc, [], _length, _ascii_only?, _special} -> "1"
      _rejected -> "0"
    end
  rescue
    _error -> "0"
  end
end

output =
  0..max_codepoint
  |> Enum.map_join("\n", fn codepoint ->
    "#{codepoint}:#{start_class.(codepoint)}:#{continues?.(codepoint)}"
  end)

File.write!(output_file, output)

IO.puts("Classes written to #{output_file}")
