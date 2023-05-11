defmodule Hologram.Compiler.Encoder do
  alias Hologram.Compiler.IR

  def encode(%IR.AtomType{value: value}) do
    encode_primitive_type(:atom, value, true)
  end

  def encode(%IR.FloatType{value: value}) do
    encode_primitive_type(:float, value)
  end

  def encode(%IR.IntegerType{value: value}) do
    encode_primitive_type(:integer, value)
  end

  defp encode_primitive_type(type, value, as_string \\ false)

  defp encode_primitive_type(type, value, false) do
    "{type: '#{type}', value: #{value}}"
  end

  defp encode_primitive_type(type, value, true) do
    value_str =
      value
      |> to_string()
      |> String.replace("'", "\\'")
      |> String.replace("\n", "\\n")

    encode_primitive_type(type, "'#{value_str}'")
  end
end
