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
    data_str = encode_as_array(data, context)
    "Type.list(#{data_str})"
  end

  def encode(%IR.MapType{data: data}, context) do
    data
    |> Enum.map(fn {key, value} ->
      "[" <> encode(key, context) <> ", " <> encode(value, context) <> "]"
    end)
    |> Enum.join(", ")
    |> StringUtils.wrap("Type.map([", "])")
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
    data_str = encode_as_array(data, context)
    "Type.tuple(#{data_str})"
  end

  def encode(%IR.Variable{name: name}, %{pattern?: true}) do
    name_str = encode_as_string(name, true)
    "Type.variable(#{name_str})"
  end

  def encode(%IR.Variable{name: name}, %{pattern?: false}) do
    "bindings.#{name}"
  end

  @doc """
  Escapes chacters which are not allowed in JS identifiers with their Unicode code points.

  Although $ (dollar sign) character is allowed in JS identifiers, we escape it as well,
  because it is used as a marker for other escaped characters.

  ## Examples

      iex> escape_js_identifier("my_fun?")
      "my_fun$63"
  """
  @spec escape_js_identifier(String.t()) :: String.t()
  def escape_js_identifier(identifier) do
    identifier
    |> String.to_charlist()
    |> Enum.map(fn code_point ->
      if allowed_in_js_identifier?(code_point) do
        to_string([code_point])
      else
        "$#{code_point}"
      end
    end)
    |> Enum.join()
  end

  # _ = 95
  # 0 = 48
  # 9 = 57
  # A = 65
  # Z = 90
  # a = 97
  # z = 122
  defp allowed_in_js_identifier?(code_point)

  defp allowed_in_js_identifier?(code_point)
       when code_point == 95 or code_point in 48..57 or code_point in 65..90 or
              code_point in 97..122 do
    true
  end

  defp allowed_in_js_identifier?(_code_point), do: false

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

  defp encode_primitive_type(type, value, as_string)

  defp encode_primitive_type(type, value, true) do
    value_str = encode_as_string(value, true)
    encode_primitive_type(type, value_str, false)
  end

  defp encode_primitive_type(type, value, false) do
    "Type.#{type}(#{value})"
  end
end
