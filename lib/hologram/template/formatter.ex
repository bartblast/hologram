defmodule Hologram.Template.Formatter do
  @moduledoc """
    A formatter for `~HOLO` sigil templates.

    Enable it by adding `Hologram.Template.Formatter` to the `plugins:` list
    in `.formatter.exs`
  """

  @behaviour Mix.Tasks.Format
  alias Hologram.Template.{Parser, Algebra}

  @impl Mix.Tasks.Format
  def features(_opts) do
    # Will `.holo` be a thing eventually?
    [sigils: [:HOLO], extensions: [".holo"]]
  end

  @impl Mix.Tasks.Format
  def format(contents, opts) do
    line_length = opts[:line_length] || 98

    case Regex.run(~r/^(\s*)(.*?)(\s*)$/s, contents) do
      [_, leading, middle, trailing] ->
        layout = if String.contains?(middle, "\n"), do: :block, else: :inline

        formatted_middle =
          middle
          |> Parser.parse_markup()
          |> Algebra.format_tokens(layout: layout)
          |> Inspect.Algebra.format(line_length)
          |> IO.iodata_to_binary()
          |> String.split("\n")
          |> Enum.map(&String.trim_trailing/1)
          |> Enum.join("\n")
          |> String.trim()

        if String.contains?(trailing, "\n") do
          leading <> formatted_middle <> "\n"
        else
          leading <> formatted_middle
        end

      _ ->
        contents
    end
  end
end
