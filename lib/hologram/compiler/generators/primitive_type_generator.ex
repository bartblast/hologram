defmodule Hologram.Compiler.PrimitiveTypeGenerator do
  def generate(type, value) do
    "{ type: '#{type}', value: #{value} }"
  end
end
