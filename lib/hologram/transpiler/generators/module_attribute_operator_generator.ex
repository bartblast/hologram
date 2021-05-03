defmodule Hologram.Transpiler.ModuleAttributeOperatorGenerator do
  alias Hologram.Transpiler.Helpers

  def generate(name, context) do
    class_name = Helpers.class_name(context[:current_module])
    "#{class_name}.$state.data.#{name}"
  end
end
