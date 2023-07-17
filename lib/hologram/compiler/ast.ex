defmodule Hologram.Compiler.AST do
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Normalizer

  @type t :: Macro.t()

  @doc """
  Given Elixir source code returns its normalized Elixir AST.

  ## Examples

      iex> for_code("1 + 2")
      {:+, [line: 1], [1, 2]}
  """
  @spec for_code(binary) :: AST.t()
  def for_code(code) do
    code
    |> Code.string_to_quoted!()
    |> Normalizer.normalize()
  end
end
