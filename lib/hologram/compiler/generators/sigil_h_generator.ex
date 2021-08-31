defmodule Hologram.Compiler.SigilHGenerator do
  alias Hologram.Compiler.Context
  alias Hologram.Template.{Generator, Parser, Transformer}

  def generate(ir, %Context{} = context) do
    ir
    |> Map.get(:params)
    |> hd()
    |> Map.get(:parts)
    |> hd()
    |> Map.get(:value)
    |> String.trim()
    |> Parser.parse!()
    |> Transformer.transform(context.aliases)
    |> Generator.generate()
  end
end
