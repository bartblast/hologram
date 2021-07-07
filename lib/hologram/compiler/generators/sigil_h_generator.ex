defmodule Hologram.Compiler.SigilHGenerator do
  alias Hologram.Template.{Generator, Parser, Transformer}

  def generate(ir, context) do
    ir
    |> Map.get(:params)
    |> hd()
    |> Map.get(:params)
    |> hd()
    |> Map.get(:value)
    |> Parser.parse!()
    |> Transformer.transform(context[:aliases])
    |> Generator.generate(context)
  end
end
