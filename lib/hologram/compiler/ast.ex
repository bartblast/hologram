defmodule Hologram.Compiler.AST do
  alias Hologram.Compiler.Normalizer
  alias Hologram.Compiler.Parser

  @doc """
  Given Elixir source code returns its Elixir AST.

  ## Examples

      iex> AST.for_code("1 + 2")
      {:+, [line: 1], [1, 2]}
  """
  def for_code(code) do
    Parser.parse!(code)
    |> Normalizer.normalize()
  end
end
