defmodule Hologram.Compiler.Serializer do
  alias Hologram.Compiler.{Context, JSEncoder, Normalizer, Opts, Transformer}

  def serialize(state) do
    # TODO: pass actual %Context{} struct received from compiler
    context = %Context{}

    Macro.escape(state)
    |> Normalizer.normalize()
    |> Transformer.transform(context)
    |> JSEncoder.encode(context, %Opts{})
  end
end
