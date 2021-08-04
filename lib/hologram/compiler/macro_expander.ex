defmodule Hologram.Compiler.MacroExpander do
  alias Hologram.Compiler.IR.MacroDefinition
  alias Hologram.Compiler.Normalizer

  def expand(%MacroDefinition{module: module, name: name}, params) do
    expand(module, name, params)
  end

  def expand(module, name, params) do
    name = if name == :__using__, do: :__using, else: name

    expanded =
      apply(module, :"MACRO-#{name}", [__ENV__] ++ params)
      |> Normalizer.normalize()

    case expanded do
      {:__block__, [], exprs} ->
        exprs
      _ ->
        [expanded]
    end
  end
end
