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

  def encode(%IR.MapType{data: data}) do
    data_str =
      data
      |> Enum.map(fn {key, value} ->
        "'#{encode_map_key(key)}': #{encode(value)}"
      end)
      |> Enum.join(", ")
      |> StringUtils.wrap("{", "}")

    "{type: 'map', data: #{data_str}}"
  end

  def encode(%IR.StringType{value: value}) do
    encode_primitive_type(:atom, value, true)
  end

  def encode(%IR.TupleType{data: data}) do
    "{type: 'tuple', data: #{encode_as_array(data)}}"
  end

  defp build_map_key(type, value) do
    value_str = encode_as_string(value, false)
    "#{type}(#{value_str})"
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

  defp encode_enum_map_key(type, data) do
    data
    |> Enum.map(&encode_map_key/1)
    |> Enum.join(",")
    |> StringUtils.wrap("#{type}(", ")")
  end

  defp encode_map_key(%IR.AtomType{value: value}) do
    build_map_key(:atom, value)
  end

  defp encode_map_key(%IR.FloatType{value: value}) do
    build_map_key(:float, value)
  end

  defp encode_map_key(%IR.IntegerType{value: value}) do
    build_map_key(:integer, value)
  end

  defp encode_map_key(%IR.ListType{data: data}) do
    encode_enum_map_key(:list, data)
  end

  defp encode_map_key(%IR.MapType{data: data}) do
    data
    |> Enum.map(fn {key, value} ->
      encode_map_key(key) <> ":" <> encode_map_key(value)
    end)
    |> Enum.join(",")
    |> StringUtils.wrap("map(", ")")
  end

  defp encode_map_key(%IR.StringType{value: value}) do
    build_map_key(:string, value)
  end

  defp encode_map_key(%IR.TupleType{data: data}) do
    encode_enum_map_key(:tuple, data)
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
