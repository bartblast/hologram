defmodule Hologram.Compiler.Hydrator do
  alias Hologram.Compiler.{Context, Generator, Normalizer, Transformer}

  def hydrate(state) do
    # TODO: pass actual %Context{} struct received from compiler
    context = %Context{module: [], uses: [], imports: [], aliases: [], attributes: []}

    Macro.escape(state)
    |> Normalizer.normalize()
    |> Transformer.transform(context)
    |> Generator.generate(context)
  end
end
