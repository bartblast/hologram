#!/usr/bin/env elixir

# Script to compare the BEAM and JavaScript script signatures and detect inconsistencies.
#
# Codepoints the BEAM marks unusable ("-") are skipped - they never reach a script-set check.
# Divergent codepoints are grouped into contiguous ranges sharing the same (elixir, javascript)
# signature pair, since the number of ranges is what an override table in the runtime costs.

ex_file = Path.join(__DIR__, "scriptsets_elixir.txt")
js_file = Path.join(__DIR__, "scriptsets_javascript.txt")

IO.puts("Comparing scriptsets_elixir.txt and scriptsets_javascript.txt...\n")

# The generators write the oracle files without a trailing newline, so splitting
# on it yields only real lines. An editor that adds one on save would otherwise
# feed an empty line to the destructuring below, which no clause matches.
parse_file = fn filename ->
  filename
  |> File.read!()
  |> String.split("\n")
  |> Enum.reject(&(&1 == ""))
  |> Enum.map(fn line ->
    [codepoint, signature] = String.split(line, ":", parts: 2)
    {String.to_integer(codepoint), signature}
  end)
  |> Map.new()
end

elixir_signatures = parse_file.(ex_file)
js_signatures = parse_file.(js_file)

usable = Enum.reject(elixir_signatures, fn {_codepoint, signature} -> signature == "-" end)

divergences =
  usable
  |> Enum.filter(fn {codepoint, elixir_signature} ->
    Map.get(js_signatures, codepoint) != elixir_signature
  end)
  |> Enum.sort_by(fn {codepoint, _signature} -> codepoint end)

group_into_ranges = fn divergences ->
  divergences
  |> Enum.reduce([], fn {codepoint, elixir_signature}, acc ->
    js_signature = Map.get(js_signatures, codepoint)
    pair = {elixir_signature, js_signature}

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
  |> Enum.map(fn {codepoint, elixir_signature} ->
    {elixir_signature, Map.get(js_signatures, codepoint)}
  end)
  |> Enum.frequencies()
  |> Enum.sort_by(fn {_pair, count} -> -count end)

summary_lines =
  Enum.map(pair_counts, fn {{elixir_signature, js_signature}, count} ->
    "  elixir=#{elixir_signature} js=#{js_signature} -> #{count} codepoints"
  end)

range_lines =
  Enum.map(ranges, fn {first, last, {elixir_signature, js_signature}} ->
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

    "#{String.pad_trailing("#{first}-#{last}", 16)} | elixir=#{elixir_signature} | js=#{js_signature}#{chars}"
  end)

output_content =
  Enum.join(
    [
      "Usable codepoints compared: #{length(usable)}",
      "Divergent codepoints: #{length(divergences)}",
      "Divergent ranges: #{length(ranges)}\n",
      "By signature pair:\n" | summary_lines
    ] ++
      ["\nRanges:\n" | range_lines],
    "\n"
  )

output_file = Path.join(__DIR__, "comparison_scriptsets.txt")
File.write!(output_file, output_content)

IO.puts(output_content |> String.split("\n") |> Enum.take(25) |> Enum.join("\n"))
IO.puts("\nResults written to comparison_scriptsets.txt")
