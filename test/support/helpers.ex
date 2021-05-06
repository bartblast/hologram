defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.Normalizer
  alias Hologram.Compiler.Parser

  def ast(code) do
    Parser.parse!(code)
    |> Normalizer.normalize()
  end
end
