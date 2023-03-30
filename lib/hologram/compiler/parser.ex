defmodule Hologram.Compiler.Parser do
  use Hologram.Commons.Parser

  @doc """
  Parses Elixir code into Elixir AST.

  ## Examples

      iex> parse("1 + 2)
      {:ok, {:+, [line: 1], [1, 2]}}

      iex> parse(".1")
      {:error, {[line: 1, column: 1], "syntax error before: ", "'.'"}}
  """
  @impl Hologram.Commons.Parser
  @spec parse(binary) :: {:ok, Macro.t()} | {:error, {keyword, binary | {binary, binary}, binary}}
  def parse(code) do
    Code.string_to_quoted(code)
  end
end
