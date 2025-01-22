defmodule Hologram.Compiler.AST do
  @moduledoc false

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

  @doc """
  Returns normalized AST of the given module.
  Specifying the module's BEAM path makes the call faster.
  """
  @spec for_module(module, charlist | nil) :: AST.t()
  def for_module(module, beam_path \\ nil) do
    input = beam_path || :code.which(module)

    input
    |> BeamFile.elixir_quoted!()
    |> Normalizer.normalize()
  end
end
