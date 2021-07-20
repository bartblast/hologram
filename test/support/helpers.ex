defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.{Context, Normalizer, Parser, Transformer}

  def ast(code) do
    Parser.parse!(code)
    |> Normalizer.normalize()
  end

  def ir(code) do
    context = %Context{module: nil, uses: [], imports: [], aliases: [], attributes: []}

    ast(code)
    |> Transformer.transform(context)
  end
end
