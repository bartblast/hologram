defmodule Hologram.Compiler.Parser do
  use Hologram.Commons.Parser

  @doc """
  Parses Elixir code into Elixir AST.

  ## Examples
      iex> Parser.parse("1 + 2)
      {:ok, {:+, [line: 1], [1, 2]}}
  """
  @impl Hologram.Commons.Parser
  def parse(code) do
    Code.string_to_quoted(code)
  end
end
