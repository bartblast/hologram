defmodule Hologram.Compiler.MacroExpander do
  alias Hologram.Compiler.IR.MacroDefinition
  alias Hologram.Compiler.Normalizer

  def expand(%MacroDefinition{module: module, name: name}, params) do
    name = if name == :__using__, do: :__using, else: name

    apply(module, :"MACRO-#{name}", [__ENV__] ++ params)
    |> Normalizer.normalize()
  end
end
