defmodule Hologram.Transpiler.ModuleAttributeOperatorGenerator do
  def generate(name, context) do
    "$state.data.#{name}"
  end
end
