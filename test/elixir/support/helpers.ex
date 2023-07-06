defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR

  defdelegate ast(code), to: AST, as: :for_code
  defdelegate ir(code, context), to: IR, as: :for_code

  @doc """
  Encodes Elixir source code to JavaScript source code.

  ## Examples

      iex> js("[1, :abc]")
      "Type.list([Type.integer(1), Type.atom(\"abc\")])"
  """
  @spec js(String.t()) :: String.t()
  def js(code) do
    code
    |> ir(%Context{})
    |> Encoder.encode(%Context{})
  end
end
