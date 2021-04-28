defmodule Hologram.Transpiler.Hydrator do
  alias Hologram.Transpiler.Generator
  alias Hologram.Transpiler.Normalizer
  alias Hologram.Transpiler.Transformer

  def hydrate(state) do
    Macro.escape(state)
    |> Normalizer.normalize()
    |> Transformer.transform()
    |> Generator.generate()
  end
end
