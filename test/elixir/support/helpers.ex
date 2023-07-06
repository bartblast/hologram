defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR

  defdelegate ast(code), to: AST, as: :for_code
  defdelegate ir(code, context), to: IR, as: :for_code

  def encode(code) do
    code
    |> ir(%Context{})
    |> Encoder.encode(%Context{})
  end
end
