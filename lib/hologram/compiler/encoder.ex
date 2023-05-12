defmodule Hologram.Compiler.Encoder do
  alias Hologram.Commons.StringUtils
  alias Hologram.Compiler.IR

  def encode(%IR.AtomType{value: value}) do
    encode_primitive_type(:atom, value, true)
  end

  def encode(%IR.FloatType{value: value}) do
    encode_primitive_type(:float, value, false)
  end

  def encode(%IR.IntegerType{value: value}) do
    encode_primitive_type(:integer, value, false)
  end

  def encode(%IR.ListType{data: data}) do
    "{type: 'list', data: #{encode_as_array(data)}}"
  end

  def encode(%IR.StringType{value: value}) do
    encode_primitive_type(:atom, value, true)
  end

  def encode(%IR.TupleType{data: data}) do
    "{type: 'tuple', data: #{encode_as_array(data)}}"
  end

  defp encode_as_array(data) do
    Enum.map(data, &encode/1)
    |> Enum.join(", ")
    |> StringUtils.wrap("[", "]")
  end

  defp encode_as_string(value, wrap)

  defp encode_as_string(value, false) do
    value
    |> to_string()
    |> String.replace("'", "\\'")
    |> String.replace("\n", "\\n")
  end

  defp encode_as_string(value, true) do
    value
    |> encode_as_string(false)
    |> StringUtils.wrap("'", "'")
  end

  defp encode_primitive_type(type, value, as_string)

  defp encode_primitive_type(type, value, false) do
    "{type: '#{type}', value: #{value}}"
  end

  defp encode_primitive_type(type, value, true) do
    value_str = encode_as_string(value, true)
    encode_primitive_type(type, value_str, false)
  end
end
