defmodule Hologram.Compiler.ModuleAttributeOperatorGenerator do
  alias Hologram.Compiler.{Context, MapKeyGenerator}
  alias Hologram.Compiler.IR.AtomType

  def generate(name, %Context{} = context) do
    key = MapKeyGenerator.generate(%AtomType{value: name}, context)
    "$state.data['#{key}']"
  end
end
