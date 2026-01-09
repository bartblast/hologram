#!/usr/bin/env elixir

# Script to compare Elixir and JavaScript uppercase mapping and detect inconsistencies

ex_file = Path.join(__DIR__, "mapping_elixir.txt")
js_file = Path.join(__DIR__, "mapping_javascript.txt")

IO.puts("Comparing mappings from mapping_elixir.txt and mapping_javascript.txt...\n")

parse_file = fn filename ->
  filename
  |> File.read!()
  |> String.split("\n")
  |> Enum.map(fn line ->
    [codepoint, result] = String.split(line, ":", parts: 2)
    {String.to_integer(codepoint), result}
  end)
  |> Map.new()
end

elixir_mapping = parse_file.(ex_file)
js_mapping = parse_file.(js_file)

inconsistencies =
  elixir_mapping
  |> Enum.filter(fn {codepoint, elixir_result} ->
    js_result = Map.get(js_mapping, codepoint)
    elixir_result != js_result
  end)
  |> Enum.sort_by(fn {codepoint, _elixir_result} -> codepoint end)

header = [
  "# NOTE: Due to Unicode character width variations, the formatting will appear",
  "# broken in text editors. For proper viewing, use: cat comparison.txt",
  String.duplicate("=", 80),
  ""
]

output = [
  "Total codepoints: #{map_size(elixir_mapping)}",
  "Inconsistencies found: #{length(inconsistencies)}\n",
  "Inconsistencies:\n",
  "Codepoint | Char    | Elixir Result | JavaScript Result",
  String.duplicate("-", 80)
]

inconsistency_lines =
  inconsistencies
  |> Enum.map(fn {codepoint, elixir_result} ->
    js_result = Map.get(js_mapping, codepoint)

    char_display =
      try do
        char = <<codepoint::utf8>>
        if String.printable?(char), do: char, else: "unprintable"
      rescue
        _error -> "invalid"
      end

    "#{String.pad_trailing(Integer.to_string(codepoint), 9)} | #{String.pad_trailing(char_display, 7)} | #{String.pad_trailing(elixir_result, 13)} | #{js_result}"
  end)

output_content = Enum.join(header ++ output ++ inconsistency_lines, "\n")

output_file = Path.join(__DIR__, "comparison.txt")
File.write!(output_file, output_content)

IO.puts(output_content)
IO.puts("\nResults written to comparison.txt")
