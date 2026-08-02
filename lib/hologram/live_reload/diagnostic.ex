defmodule Hologram.LiveReload.Diagnostic do
  @moduledoc false

  @typedoc """
  A run of text and the tone it reads in.
  """
  @type segment :: %{tone: atom, text: String.t()}

  # The escape sequences the compiler colors its diagnostics with when ANSI is
  # enabled. They carry no meaning outside a terminal, and would otherwise be
  # shown as the characters they are made of.
  @ansi_escapes_regex ~r/\e\[[0-9;]*[a-zA-Z]/

  # The gutter a source excerpt opens with, holding the line number, as in
  # "  3 │     foo()".
  @source_excerpt_regex ~r/^(\s*\d+\s*│\s?)(.*)$/u

  @doc """
  Returns the compiler's output as lines, each a list of segments.

  Every line reads in one of four tones:

    * `:banner` - what went wrong, as in `** (CompileError) ...`, `error: ...`
      and `warning: ...`
    * `:body` - the source the diagnostic points at
    * `:chrome` - the scaffolding holding the rest apart: line-number gutters,
      carets and section rules
    * `:meta` - where it points, as in `└─ lib/my_app.ex:3:5: MyApp.bar/0`

  A line matching none of them reads in `:body`, so output in a shape
  this doesn't know is still shown as it was written.
  """
  @spec to_lines(String.t()) :: [[segment]]
  def to_lines(output) do
    output
    |> strip_ansi_escapes()
    |> String.split("\n")
    |> Enum.map(&to_segments/1)
  end

  defp segment(tone, text), do: %{tone: tone, text: text}

  defp strip_ansi_escapes(text) do
    Regex.replace(@ansi_escapes_regex, text, "")
  end

  defp to_segments(line) do
    trimmed = String.trim_leading(line)

    cond do
      String.starts_with?(trimmed, ["** (", "error:", "warning:"]) ->
        [segment(:banner, line)]

      String.starts_with?(trimmed, ["== ", "│"]) ->
        [segment(:chrome, line)]

      String.starts_with?(trimmed, "└─") ->
        [segment(:meta, line)]

      true ->
        to_source_excerpt_segments(line)
    end
  end

  defp to_source_excerpt_segments(line) do
    case Regex.run(@source_excerpt_regex, line) do
      [_match, gutter, source] -> [segment(:chrome, gutter), segment(:body, source)]
      nil -> [segment(:body, line)]
    end
  end
end
