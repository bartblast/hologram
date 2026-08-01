#!/usr/bin/env elixir

# Script to compare the BEAM and JavaScript identifier classifications and detect inconsistencies.
#
# Divergent codepoints are grouped into contiguous ranges sharing the same (elixir, javascript)
# class pair, since the number of ranges - not the number of codepoints - is what an override
# table in the runtime costs.

ex_file = Path.join(__DIR__, "classes_elixir.txt")
js_file = Path.join(__DIR__, "classes_javascript.txt")

IO.puts("Comparing classes_elixir.txt and classes_javascript.txt...\n")

# The generators write the oracle files without a trailing newline, so splitting
# on it yields only real lines. An editor that adds one on save would otherwise
# feed an empty line to the destructuring below, which no clause matches.
parse_file = fn filename ->
  filename
  |> File.read!()
  |> String.split("\n")
  |> Enum.reject(&(&1 == ""))
  |> Enum.map(fn line ->
    [codepoint, start, continues] = String.split(line, ":", parts: 3)
    {String.to_integer(codepoint), {start, continues}}
  end)
  |> Map.new()
end

elixir_classes = parse_file.(ex_file)
js_classes = parse_file.(js_file)

divergences =
  elixir_classes
  |> Enum.filter(fn {codepoint, elixir_class} ->
    Map.get(js_classes, codepoint) != elixir_class
  end)
  |> Enum.sort_by(fn {codepoint, _class} -> codepoint end)

group_into_ranges = fn divergences ->
  divergences
  |> Enum.reduce([], fn {codepoint, elixir_class}, acc ->
    js_class = Map.get(js_classes, codepoint)
    pair = {elixir_class, js_class}

    case acc do
      [{first, last, ^pair} | rest] when codepoint == last + 1 ->
        [{first, codepoint, pair} | rest]

      _acc ->
        [{codepoint, codepoint, pair} | acc]
    end
  end)
  |> Enum.reverse()
end

ranges = group_into_ranges.(divergences)

pair_counts =
  divergences
  |> Enum.map(fn {codepoint, elixir_class} -> {elixir_class, Map.get(js_classes, codepoint)} end)
  |> Enum.frequencies()
  |> Enum.sort_by(fn {_pair, count} -> -count end)

format_class = fn {start, continues} -> "#{start}:#{continues}" end

summary_lines =
  Enum.map(pair_counts, fn {{elixir_class, js_class}, count} ->
    "  elixir=#{format_class.(elixir_class)} js=#{format_class.(js_class)} -> #{count} codepoints"
  end)

range_lines =
  Enum.map(ranges, fn {first, last, {elixir_class, js_class}} ->
    chars =
      if last - first <= 3 do
        first..last
        |> Enum.map_join("", fn codepoint ->
          char = <<codepoint::utf8>>
          if String.printable?(char), do: char, else: "?"
        end)
        |> then(&" (#{&1})")
      else
        ""
      end

    "#{String.pad_trailing("#{first}-#{last}", 16)} | elixir=#{format_class.(elixir_class)} | js=#{format_class.(js_class)}#{chars}"
  end)

output_content =
  Enum.join(
    [
      "Total codepoints: #{map_size(elixir_classes)}",
      "Divergent codepoints: #{length(divergences)}",
      "Divergent ranges: #{length(ranges)}\n",
      "By class pair:\n" | summary_lines
    ] ++
      ["\nRanges:\n" | range_lines],
    "\n"
  )

output_file = Path.join(__DIR__, "comparison_classes.txt")
File.write!(output_file, output_content)

IO.puts(output_content |> String.split("\n") |> Enum.take(25) |> Enum.join("\n"))
IO.puts("\nResults written to comparison_classes.txt")
