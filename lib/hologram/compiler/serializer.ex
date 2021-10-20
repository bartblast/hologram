defmodule Hologram.Compiler.Serializer do
  alias Hologram.Compiler.{Context, Encoder, Normalizer, Opts, Transformer}

  def serialize(state) do
    # TODO: pass actual %Context{} struct received from compiler
    context = %Context{}

    Macro.escape(state)
    |> Normalizer.normalize()
    |> Transformer.transform(context)
    |> Encoder.encode(context, %Opts{})
  end
end
