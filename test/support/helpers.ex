defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.{Context, Normalizer, Parser, Transformer}

  def ast(code) do
    Parser.parse!(code)
    |> Normalizer.normalize()
  end

  def ir(code) do
    ast(code)
    |> Transformer.transform(%Context{})
  end
end
