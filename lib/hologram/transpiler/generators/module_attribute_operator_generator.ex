defmodule Hologram.Transpiler.ModuleAttributeOperatorGenerator do
  alias Hologram.Transpiler.Helpers

  def generate(name, context) do
    context[:current_module]
    |> Helpers.class_name()
    |> Kernel.<>(".$#{name}")
  end
end
