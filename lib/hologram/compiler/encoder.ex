defmodule Hologram.Compiler.Encoder do
  alias Hologram.Compiler.IR

  def encode(%IR.IntegerType{value: value}) do
    encode_primitive_type(:integer, value)
  end

  defp encode_primitive_type(type, value) do
    "{type: '#{type}', value: #{value}}"
  end
end
