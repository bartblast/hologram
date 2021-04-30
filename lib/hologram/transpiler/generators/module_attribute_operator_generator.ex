defmodule Hologram.Transpiler.ModuleAttributeOperatorGenerator do
  alias Hologram.Transpiler.Generator

  def generate(name, context) do
    context[:module_attributes]
    |> Enum.find(&(&1.name == name))
    |> Map.get(:value)
    |> Generator.generate(context)
  end
end
