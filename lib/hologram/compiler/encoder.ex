defmodule Hologram.Compiler.Encoder do
  alias Hologram.Commons.StringUtils
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR

  @spec encode(IR.t(), Context.t()) :: String.t()
  def encode(ir, context)

  def encode(%IR.AtomType{value: value}, _context) do
    encode_primitive_type(:atom, value, true)
  end

  def encode(%IR.FloatType{value: value}, _context) do
    encode_primitive_type(:float, value, false)
  end

  def encode(%IR.IntegerType{value: value}, _context) do
    encode_primitive_type(:integer, value, false)
  end

  def encode(%IR.ListType{data: data}, context) do
    "Type.list(#{encode_as_array(data, context)})"
  end

  def encode(%IR.MapType{data: data}, context) do
    data_str =
      data
      |> Enum.map(fn {key, value} ->
        "'#{encode_map_key(key)}': #{encode(value, context)}"
      end)
      |> Enum.join(", ")
      |> StringUtils.wrap("{", "}")

    "{type: 'map', data: #{data_str}}"
  end

  def encode(%IR.MatchOperator{left: left, right: right}, context) do
    left = encode(left, %{context | pattern?: true})
    right = encode(right, context)

    "Interpreter.matchOperator(#{left}, #{right})"
  end

  def encode(%IR.StringType{value: value}, _context) do
    encode_primitive_type(:string, value, true)
  end

  def encode(%IR.TupleType{data: data}, context) do
    "{type: 'tuple', data: #{encode_as_array(data, context)}}"
  end

  def encode(%IR.Variable{name: name}, %{pattern?: true}) do
    name_str = encode_as_string(name, true)
    "{type: 'variable', name: #{name_str}}"
  end

  def encode(%IR.Variable{name: name}, %{pattern?: false}) do
    "bindings.#{name}"
  end

  defp build_map_key(type, value) do
    value_str = encode_as_string(value, false)
    "#{type}(#{value_str})"
  end

  defp encode_as_array(data, context) do
    Enum.map(data, &encode(&1, context))
    |> Enum.join(", ")
    |> StringUtils.wrap("[", "]")
  end

  defp encode_as_string(value, wrap)

  defp encode_as_string(value, false) do
    value
    |> to_string()
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  defp encode_as_string(value, true) do
    value
    |> encode_as_string(false)
    |> StringUtils.wrap("\"", "\"")
  end

  defp encode_enum_map_key(type, data) do
    data
    |> Enum.map(&encode_map_key/1)
    |> Enum.join(",")
    |> StringUtils.wrap("#{type}(", ")")
  end

  # We don't have to pass context when building map keys,
  # to determine whether to encode IR.Variable as a value or an assignment,
  # because variables cannot be used in map keys inside a pattern.
  # Map keys in patterns can only be literals (such as atoms, strings, tuples, and the like)
  # or an existing variable matched with the pin operator (such as ^some_var).
  defp encode_map_key(ir)

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

  defp encode_primitive_type(type, value, true) do
    value_str = encode_as_string(value, true)
    encode_primitive_type(type, value_str, false)
  end

  defp encode_primitive_type(type, value, false) do
    "Type.#{type}(#{value})"
  end
end
