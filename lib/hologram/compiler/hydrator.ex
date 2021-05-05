defmodule Hologram.Compiler.Hydrator do
  alias Hologram.Compiler.Generator
  alias Hologram.Compiler.Normalizer
  alias Hologram.Compiler.Transformer

  def hydrate(state) do
    Macro.escape(state)
    |> Normalizer.normalize()
    |> Transformer.transform()
    |> Generator.generate()
  end
end
