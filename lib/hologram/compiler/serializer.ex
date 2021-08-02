defmodule Hologram.Compiler.Serializer do
  alias Hologram.Compiler.{Context, Generator, Normalizer, Opts, Transformer}

  def serialize(state) do
    # TODO: pass actual %Context{} struct received from compiler
    context = %Context{}

    Macro.escape(state)
    |> Normalizer.normalize()
    |> Transformer.transform(context)
    |> Generator.generate(context, %Opts{})
  end
end
