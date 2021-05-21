defmodule Hologram.Template.NodeListGenerator do
  alias Hologram.Compiler.{Normalizer, Transformer}
  alias Hologram.Compiler.IR.ModuleAttributeDefinition
  alias Hologram.Template.Generator

  def generate(nodes, state) do
    module_attributes =
      Enum.map(state, fn {key, value} ->
        value =
          Macro.escape(value)
          |> Normalizer.normalize()
          |> Transformer.transform()

        %ModuleAttributeDefinition{name: key, value: value}
      end)

    context = [module_attributes: module_attributes]

    nodes_js =
      Enum.map(nodes, &Generator.generate(&1, context))
      |> Enum.join(", ")

    "[#{nodes_js}]"
  end
end
