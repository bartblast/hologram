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

  def encode(%IR.StringType{value: value}) do
    encode_primitive_type(:atom, value, true)
  end

  defp encode_as_string(value) do
    value_str =
      value
      |> to_string()
      |> String.replace("'", "\\'")
      |> String.replace("\n", "\\n")

    "'#{value_str}'"
  end

  defp encode_primitive_type(type, value, as_string \\ false)

  defp encode_primitive_type(type, value, false) do
    "{type: '#{type}', value: #{value}}"
  end

  defp encode_primitive_type(type, value, true) do
    value_encoded_as_string = encode_as_string(value)
    encode_primitive_type(type, value_encoded_as_string)
  end
end
