#!/usr/bin/env elixir

# Script to generate character to uppercase mapping using :string.titlecase/1
# Output format: codepoint:uppercased_codepoint(s) or codepoint:-

output_file = Path.join(__DIR__, "upcase_mappings_elixir.txt")

# Generate mappings for all Unicode codepoints (0 to 0x10FFFF = 1,114,111)
max_codepoint = 0x10FFFF

IO.puts("Generating upcase mapping for codepoints 0 to #{max_codepoint}...")

output =
  0..max_codepoint
  |> Enum.map_join("\n", fn codepoint ->
    try do
      result_str =
        <<codepoint::utf8>>
        |> :string.titlecase()
        |> :unicode.characters_to_list()
        |> Enum.map(&Integer.to_string/1)
        |> Enum.join(",")

      "#{codepoint}:#{result_str}"
    rescue
      _error -> "#{codepoint}:-"
    end
  end)

File.write!(output_file, output)

IO.puts("Mapping written to #{output_file}")
