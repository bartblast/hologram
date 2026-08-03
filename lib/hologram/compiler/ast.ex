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
  Specifying the module's BEAM path or BEAM binary makes the call faster.
  """
  # TODO: Narrow the spec back to charlist, and rename the param back to
  # beam_path, when Hologram.Compiler.resolve_beam_source/2 goes (see the
  # removal note there) - nothing passes a BEAM binary here after that.
  @spec for_module(module, charlist | binary | nil) :: AST.t()
  def for_module(module, beam_source \\ nil) do
    input = beam_source || :code.which(module)

    input
    |> BeamFile.elixir_quoted!()
    |> Normalizer.normalize()
  end
end
