defmodule Hologram.Compiler.Serializer do
  alias Hologram.Compiler.{Context, Generator, Normalizer, Transformer}

  def serialize(state) do
    # TODO: pass actual %Context{} struct received from compiler
    context = %Context{module: nil, uses: [], imports: [], aliases: [], attributes: []}

    Macro.escape(state)
    |> Normalizer.normalize()
    |> Transformer.transform(context)
    |> Generator.generate(context)
  end
end
