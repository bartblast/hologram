defmodule Hologram.Compiler.SigilHGenerator do
  alias Hologram.Compiler.Context
  alias Hologram.Template.{Generator, Parser, Transformer}

  def generate(ir, %Context{} = context) do
    ir
    |> Map.get(:params)
    |> hd()
    |> Map.get(:params)
    |> hd()
    |> Map.get(:value)
    |> Parser.parse!()
    |> Transformer.transform(context.aliases)
    |> Generator.generate()
  end
end
