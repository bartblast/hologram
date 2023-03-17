defmodule Hologram.Compiler.AST do
  alias Hologram.Compiler.Normalizer
  alias Hologram.Compiler.Parser

  def from_code(code) do
    Parser.parse!(code)
    |> Normalizer.normalize()
  end
end
