defmodule Hologram.Transpiler.ModuleAttributeOperatorGenerator do
  alias Hologram.Transpiler.AST.AtomType
  alias Hologram.Transpiler.MapKeyGenerator

  def generate(name, context) do
    key = MapKeyGenerator.generate(%AtomType{value: name})
    "$state.data['#{key}']"
  end
end
