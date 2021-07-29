defmodule Hologram.Compiler.Serializer do
  alias Hologram.Compiler.{Context, Generator, Normalizer, Transformer}

  def serialize(state) do
    # TODO: pass actual %Context{} struct received from compiler

    Macro.escape(state)
    |> Normalizer.normalize()
    |> Transformer.transform(%Context{})
    |> Generator.generate(%Context{})
  end
end
