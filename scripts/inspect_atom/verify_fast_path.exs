# Script to verify the fast path the client's atom inspection takes against the BEAM.
#
# The client renders an atom without asking Elixir when its name is a plain ASCII identifier -
# a lowercase letter or underscore, then letters, digits and underscores, optionally closed by
# "?" or "!". Everything else it hands to Macro.inspect_atom/3, which is the server's own code,
# so only this fast path can disagree with the server. The script proves it doesn't, over:
#
#   * every such name of 1 and 2 characters, plain and with each closing punctuation
#   * every such name of 3 characters
#   * the words Elixir gives meaning to (operators, keywords), which the pattern also matches
#   * the identifiers real applications use, taken from the tokenizer verification corpus
#
# nil, true and false are left out of the literal format on purpose: they render as themselves,
# with no leading colon, and the client answers them before the fast path is reached.

first_chars = [?_ | Enum.to_list(?a..?z)]
rest_chars = first_chars ++ Enum.to_list(?A..?Z) ++ Enum.to_list(?0..?9)
closings = [~c"", ~c"?", ~c"!"]

singles =
  for char <- first_chars, closing <- closings, do: [char] ++ closing

doubles =
  for first <- first_chars, second <- rest_chars, closing <- closings do
    [first, second] ++ closing
  end

triples =
  for first <- first_chars, second <- rest_chars, third <- rest_chars do
    [first, second, third]
  end

# Words Elixir treats as operators or keywords, which the pattern matches like any other name.
special_words =
  ~w(after and catch do else end fn in not or rescue when unless if case cond try receive raise
     use import require alias defmodule def defp defmacro __MODULE__ __ENV__)

app_names =
  case File.read(__DIR__ <> "/../identifier_tokenizer/verification_elixir.txt") do
    {:ok, contents} ->
      contents
      |> String.split("\n")
      |> Enum.flat_map(fn line ->
        case String.split(line, "|") do
          [input | _rest] ->
            codepoints =
              input
              |> String.split(",")
              |> Enum.flat_map(fn part ->
                case Integer.parse(part) do
                  # Only ASCII can reach the fast path, and the corpus carries
                  # lone surrogates that don't convert to a string at all.
                  {codepoint, ""} when codepoint < 128 -> [codepoint]
                  _other -> []
                end
              end)

            [List.to_string(codepoints)]

          _other ->
            []
        end
      end)

    {:error, _reason} ->
      IO.puts("(the tokenizer corpus isn't present - skipping the real-world names)")
      []
  end

names =
  (Enum.map(singles ++ doubles ++ triples, &List.to_string/1) ++ special_words ++ app_names)
  |> Enum.uniq()
  |> Enum.filter(&Regex.match?(~r/^[a-z_][a-zA-Z0-9_]*[?!]?$/, &1))

IO.puts("Checking #{length(names)} names against the three source formats...")

mismatches =
  Enum.flat_map(names, fn name ->
    atom = String.to_atom(name)

    expected = [
      {:literal, ":" <> name},
      {:key, name <> ":"},
      {:remote_call, name}
    ]

    Enum.flat_map(expected, fn {format, expected_output} ->
      # nil, true and false never reach the fast path in literal format.
      if format == :literal and name in ~w(nil true false) do
        []
      else
        actual_output = Macro.inspect_atom(format, atom)

        if actual_output == expected_output do
          []
        else
          [{name, format, expected_output, actual_output}]
        end
      end
    end)
  end)

Enum.each(Enum.take(mismatches, 20), fn {name, format, expected, actual} ->
  IO.puts("MISMATCH #{inspect(name)} as #{format}: expected #{expected}, got #{actual}")
end)

# The client renders an alias without asking Elixir either, dropping the "Elixir." prefix unless
# what follows is Elixir itself. The names checked here cover both, the segments that make a name
# an alias at all, and the ones that only look like it.
alias_names =
  [
    "Elixir",
    "Elixir.Elixir",
    "Elixir.Elixir.Foo",
    "Elixir.ElixirFoo",
    "Elixir.Foo",
    "Elixir.Foo.Bar",
    "Elixir.Foo.Bar.Baz",
    "Elixir.F",
    "Elixir.Foo1",
    "Elixir.Foo_Bar",
    "Elixir.Foo?",
    "Elixir.foo",
    "Elixir.",
    "Elixir.Foo.",
    "Elixir.Foo.bar",
    "ElixirFoo",
    "Elixir Foo"
  ] ++ Enum.map(["String", "Kernel", "Hologram.Component"], &("Elixir." <> &1))

alias_mismatches =
  Enum.flat_map(Enum.uniq(alias_names), fn name ->
    is_alias = Regex.match?(~r/^Elixir(\.[A-Z][a-zA-Z0-9_]*)*$/, name)

    is_elixir_itself =
      name in ["Elixir", "Elixir.Elixir"] or String.starts_with?(name, "Elixir.Elixir.")

    expected_output =
      cond do
        not is_alias -> Macro.inspect_atom(:literal, String.to_atom(name))
        is_elixir_itself -> name
        true -> String.replace_prefix(name, "Elixir.", "")
      end

    actual_output = Macro.inspect_atom(:literal, String.to_atom(name))

    if actual_output == expected_output do
      []
    else
      [{name, :literal, expected_output, actual_output}]
    end
  end)

Enum.each(alias_mismatches, fn {name, format, expected, actual} ->
  IO.puts("MISMATCH #{inspect(name)} as #{format}: expected #{expected}, got #{actual}")
end)

IO.puts("Checked #{length(Enum.uniq(alias_names))} alias-shaped names.")

if mismatches == [] and alias_mismatches == [] do
  IO.puts("OK: the fast paths match the server on every name")
else
  IO.puts("FAIL: #{length(mismatches) + length(alias_mismatches)} mismatches")
  System.halt(1)
end
