defmodule Hologram.Compiler.ModuleAttributeOperatorGenerator do
  alias Hologram.Compiler.AST.AtomType
  alias Hologram.Compiler.MapKeyGenerator

  def generate(name, context) do
    key = MapKeyGenerator.generate(%AtomType{value: name})
    "$state.data['#{key}']"
  end
end
