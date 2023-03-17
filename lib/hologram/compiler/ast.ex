defmodule Hologram.Compiler.AST do
  alias Hologram.Compiler.Normalizer
  alias Hologram.Compiler.Parser

  @doc """
  Converts Elixir code into Elixir AST.

  ## Examples

      iex> AST.from_code("1 + 2")
      {:+, [line: 1], [1, 2]}
  """
  def from_code(code) do
    Parser.parse!(code)
    |> Normalizer.normalize()
  end
end
