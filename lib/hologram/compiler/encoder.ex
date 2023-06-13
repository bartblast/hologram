defmodule Hologram.Compiler.Encoder do
  alias Hologram.Commons.StringUtils
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR

  @doc """
  Encodes Elixir IR to JavaScript source code.

  ## Examples

      iex> ir = %IR.ListType{
      ...>   data: [
      ...>     %IR.IntegerType{value: 1},
      ...>     %IR.AtomType{value: :abc}
      ...>   ]
      ...> }
      iex> encode(ir, %Context{})
      "Type.list([Type.integer(1), Type.atom(\"abc\")])"
  """
  @spec encode(IR.t(), Context.t()) :: String.t()
  def encode(ir, context)

  def encode(%IR.AnonymousFunctionClause{} = clause, context) do
    params = encode_as_array(clause.params, %{context | pattern?: true})

    guard =
      if clause.guard do
        guard_expr_js = encode(clause.guard, context)
        "(vars) => #{guard_expr_js}"
      else
        "null"
      end

    body_block_js = encode(clause.body, context)
    body = "(vars) => #{body_block_js}"

    "{params: #{params}, guard: #{guard}, body: #{body}}"
  end

  def encode(%IR.AtomType{value: value}, _context) do
    encode_primitive_type(:atom, value, true)
  end

  # See: https://hexdocs.pm/elixir/1.14.5/Kernel.SpecialForms.html#%3C%3C%3E%3E/1
  def encode(
        %IR.BitstringSegment{value: %IR.StringType{value: value}, modifiers: modifiers},
        %{pattern?: false} = context
      ) do
    value_str = encode_primitive_type(:string, value, true)
    encode_bitstring_segment(value_str, modifiers, context)
  end

  # See: https://hexdocs.pm/elixir/1.14.5/Kernel.SpecialForms.html#%3C%3C%3E%3E/1
  def encode(
        %IR.BitstringSegment{value: value, modifiers: modifiers},
        %{pattern?: false} = context
      ) do
    value_str = encode(value, context)
    encode_bitstring_segment(value_str, modifiers, context)
  end

  def encode(%IR.BitstringType{segments: segments}, context) do
    segments
    |> Enum.map_join(", ", &encode(&1, context))
    |> StringUtils.wrap("Type.bitstring([", "])")
  end

  def encode(%IR.Block{expressions: exprs}, context) do
    exprs =
      if exprs == [] do
        [%IR.AtomType{value: nil}]
      else
        exprs
      end

    expr_count = Enum.count(exprs)

    body =
      exprs
      |> Enum.with_index()
      |> Enum.map_join("", fn {expr, idx} ->
        expr_str = encode(expr, context)

        if idx == expr_count - 1 do
          "\nreturn #{expr_str};"
        else
          "\n#{expr_str};"
        end
      end)

    "{#{body}\n}"
  end

  def encode(%IR.ConsOperator{head: head, tail: tail}, %{pattern?: true} = context) do
    "Type.consPattern(#{encode(head, context)}, #{encode(tail, context)})"
  end

  def encode(%IR.ConsOperator{head: head, tail: tail}, %{pattern?: false} = context) do
    "Interpreter.consOperator(#{encode(head, context)}, #{encode(tail, context)}))"
  end

  def encode(%IR.FloatType{value: value}, _context) do
    encode_primitive_type(:float, value, false)
  end

  def encode(%IR.IntegerType{value: value}, _context) do
    encode_primitive_type(:integer, "#{value}n", false)
  end

  def encode(%IR.ListType{data: data}, context) do
    data_str = encode_as_array(data, context)
    "Type.list(#{data_str})"
  end

  def encode(%IR.LocalFunctionCall{function: function, args: args}, %{module: module} = context) do
    callable = encode_as_class_name(module)
    encode_function_call(callable, function, args, context)
  end

  def encode(%IR.MapType{data: data}, context) do
    data
    |> Enum.map_join(", ", fn {key, value} ->
      "[" <> encode(key, context) <> ", " <> encode(value, context) <> "]"
    end)
    |> StringUtils.wrap("Type.map([", "])")
  end

  def encode(%IR.MatchOperator{left: left, right: right}, context) do
    left = encode(left, %{context | pattern?: true})
    right = encode(right, context)

    "Interpreter.matchOperator(#{left}, #{right})"
  end

  def encode(%IR.MatchPlaceholder{}, _context) do
    "Type.matchPlaceholder()"
  end

  def encode(
        %IR.RemoteFunctionCall{
          module: %IR.AtomType{value: module},
          function: function,
          args: args
        },
        context
      ) do
    callable = encode_as_class_name(module)
    encode_function_call(callable, function, args, context)
  end

  def encode(
        %IR.RemoteFunctionCall{module: %IR.Variable{} = variable, function: function, args: args},
        context
      ) do
    callable = encode(variable, context)
    encode_function_call(callable, function, args, context)
  end

  def encode(%IR.StringType{value: value}, _context) do
    encode_primitive_type(:bitstring, value, true)
  end

  def encode(%IR.TupleType{data: data}, context) do
    data_str = encode_as_array(data, context)
    "Type.tuple(#{data_str})"
  end

  def encode(%IR.Variable{name: name}, %{pattern?: true}) do
    name_str = encode_as_string(name, true)
    "Type.variablePattern(#{name_str})"
  end

  def encode(%IR.Variable{name: name}, %{pattern?: false}) do
    "vars.#{name}"
  end

  @doc """
  Encodes an Elixir alias as a class name.

  - This function converts the `alias_atom` to a string using `to_string/1`.
  - If the resulting `alias_str` starts with a lowercase letter, it prefixes it with `"Erlang."`.
  - Finally, any dots (`.`) in the `prefixed_alias_str` are replaced with underscores (`_`).

  ## Parameters

  - `alias_atom` - The Elixir alias to be encoded as a class name.

  ## Returns

  The encoded class name.

  ## Examples

      iex> encode_as_class_name(Aaa.Bbb.Ccc)
      "Elixir_Aaa_Bbb_Ccc"

      iex> encode_as_class_name(:mymodule)
      "Erlang_Mymodule"
  """
  @spec encode_as_class_name(module | atom) :: String.t()
  def encode_as_class_name(alias_atom) do
    alias_str = to_string(alias_atom)

    prefixed_alias_str =
      if StringUtils.starts_with_lowercase?(alias_str) do
        "Erlang." <> String.capitalize(alias_str)
      else
        alias_str
      end

    String.replace(prefixed_alias_str, ".", "_")
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
    |> Enum.map_join("", fn code_point ->
      if allowed_in_js_identifier?(code_point) do
        to_string([code_point])
      else
        "$#{code_point}"
      end
    end)
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
    data
    |> Enum.map_join(", ", &encode(&1, context))
    |> StringUtils.wrap("[", "]")
  end

  defp encode_as_string(value, wrap)

  defp encode_as_string(nil, false) do
    "nil"
  end

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

  defp encode_bitstring_modifier({:size, size}, context) do
    "size: #{encode(size, context)}"
  end

  defp encode_bitstring_modifier({:unit, unit}, _context) do
    "unit: #{unit}n"
  end

  defp encode_bitstring_modifier({name, value}, _context) do
    ~s(#{name}: "#{value}")
  end

  defp encode_bitstring_segment(value_str, modifiers, context) do
    modifiers_str =
      modifiers
      |> Enum.map_join(", ", &encode_bitstring_modifier(&1, context))
      |> StringUtils.wrap("{", "}")

    "Type.bitstringSegment(#{value_str}, #{modifiers_str})"
  end

  defp encode_function_call(callable, function, args, context) do
    args_js = encode_as_array(args, context)
    "#{callable}.#{function}(#{args_js})"
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
