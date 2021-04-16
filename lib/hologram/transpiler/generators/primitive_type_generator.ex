defmodule Hologram.Transpiler.Generators.PrimitiveTypeGenerator do
  def generate(type, value) do
    "{ type: '#{type}', value: #{value} }"
  end
end
