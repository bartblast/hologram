defmodule Hologram.Compiler.Encoder do
  if Application.compile_env(:hologram, :debug_encoder) do
    use Interceptor.Annotated,
      config: %{
        {Hologram.Compiler.Encoder, :encode, 2} => [
          on_success: {Hologram.Compiler.Encoder, :debug, 3},
          on_error: {Hologram.Compiler.Encoder, :debug, 3}
        ]
      }
  end

  alias Hologram.Commons.IntegerUtils
  alias Hologram.Commons.StringUtils
  alias Hologram.Compiler.Analyzer
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
  @intercept true
  @spec encode(IR.t(), Context.t()) :: String.t()
  def encode(ir, context)

  def encode(%IR.AnonymousFunctionCall{function: function, args: args}, context) do
    function_js = encode(function, context)
    args_js = encode_as_array(args, context)

    "Interpreter.callAnonymousFunction(#{function_js}, #{args_js})"
  end

  def encode(%IR.AnonymousFunctionType{arity: arity, clauses: clauses}, context) do
    clauses_js = encode_as_array(clauses, context)
    "Type.anonymousFunction(#{arity}, #{clauses_js}, vars)"
  end

  def encode(%IR.AtomType{value: value}, _context) do
    encode_primitive_type(:atom, value, true)
  end

  # See: https://hexdocs.pm/elixir/1.14.5/Kernel.SpecialForms.html#%3C%3C%3E%3E/1
  def encode(
        %IR.BitstringSegment{value: %IR.StringType{value: value}, modifiers: modifiers},
        context
      ) do
    value_str = encode_primitive_type(:string, value, true)
    encode_bitstring_segment(value_str, modifiers, context)
  end

  # See: https://hexdocs.pm/elixir/1.14.5/Kernel.SpecialForms.html#%3C%3C%3E%3E/1
  def encode(
        %IR.BitstringSegment{value: value, modifiers: modifiers},
        context
      ) do
    value_str = encode(value, context)
    encode_bitstring_segment(value_str, modifiers, context)
  end

  def encode(%IR.BitstringType{segments: segments}, %{pattern?: true} = context) do
    segments
    |> encode_bitstring_segments(context)
    |> StringUtils.wrap("Type.bitstringPattern([", "])")
  end

  def encode(%IR.BitstringType{segments: segments}, %{pattern?: false} = context) do
    segments
    |> encode_bitstring_segments(context)
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
        # If the expression contains variables that are used both as patterns (in match operator)
        # and as values (value access), then we need to take a snapshot of these variables
        # before evaluating the expression, and then use that snapshot for accessing variable values.

        %{var_patterns: var_patterns, var_values: var_values} = Analyzer.analyze(expr)

        use_vars_snapshot? =
          var_patterns
          |> MapSet.intersection(var_values)
          |> Enum.any?()

        output =
          if use_vars_snapshot? do
            "\nInterpreter.takeVarsSnapshot(vars);"
          else
            ""
          end

        context =
          if use_vars_snapshot? do
            %{context | use_vars_snapshot?: true}
          else
            context
          end

        expr_str = encode(expr, context)

        output =
          if idx == expr_count - 1 do
            output <> "\nreturn "
          else
            output <> "\n"
          end

        output <> expr_str <> ";"
      end)

    "{#{body}\n}"
  end

  def encode(%IR.Case{condition: condition, clauses: clauses}, context) do
    condition_js = encode(condition, context)
    clauses_js = encode_as_array(clauses, context)

    "Interpreter.case(#{condition_js}, #{clauses_js})"
  end

  def encode(%IR.Clause{} = clause, context) do
    match = encode(clause.match, %{context | pattern?: true})
    guards = encode_as_array(clause.guards, context, &encode_closure/2)
    body = encode_closure(clause.body, context)

    "{match: #{match}, guards: #{guards}, body: #{body}}"
  end

  def encode(%IR.Comprehension{} = comprehension, context) do
    generators = encode_as_array(comprehension.generators, context)
    filters = encode_as_array(comprehension.filters, context)
    collectable = encode(comprehension.collectable, context)
    unique = comprehension.unique.value
    mapper = encode_closure(comprehension.mapper, context)

    "Interpreter.comprehension(#{generators}, #{filters}, #{collectable}, #{unique}, #{mapper}, vars)"
  end

  def encode(%IR.ComprehensionFilter{expression: expr}, context) do
    encode_closure(expr, context)
  end

  def encode(%IR.Cond{clauses: clauses_ir}, context) do
    clauses_js = encode_as_array(clauses_ir, context)
    "Interpreter.cond(#{clauses_js})"
  end

  def encode(%IR.CondClause{condition: condition_ir, body: body_ir}, context) do
    condition_js = encode_closure(condition_ir, context)
    body_js = encode_closure(body_ir, context)

    "{condition: #{condition_js}, body: #{body_js}}"
  end

  def encode(%IR.ConsOperator{head: head, tail: tail}, %{pattern?: true} = context) do
    "Type.consPattern(#{encode(head, context)}, #{encode(tail, context)})"
  end

  def encode(%IR.ConsOperator{head: head, tail: tail}, %{pattern?: false} = context) do
    "Interpreter.consOperator(#{encode(head, context)}, #{encode(tail, context)})"
  end

  def encode(%IR.DotOperator{left: left, right: right}, context) do
    left_js = encode(left, context)
    right_js = encode(right, context)

    "Interpreter.dotOperator(#{left_js}, #{right_js})"
  end

  def encode(%IR.FloatType{value: value}, _context) do
    encode_primitive_type(:float, value, false)
  end

  def encode(%IR.FunctionClause{} = clause, context) do
    params = encode_as_array(clause.params, %{context | pattern?: true})
    guards = encode_as_array(clause.guards, context, &encode_closure/2)
    body = encode_closure(clause.body, context)

    "{params: #{params}, guards: #{guards}, body: #{body}}"
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

  def encode(%IR.MatchOperator{left: left, right: right}, %{match_operator?: true} = context) do
    left = encode(left, %{context | pattern?: true})
    right = encode(right, context)

    "Interpreter.matchOperator(#{right}, #{left}, vars, false)"
  end

  def encode(%IR.MatchOperator{left: left, right: right}, context) do
    left = encode(left, %{context | match_operator?: true, pattern?: true})
    right = encode(right, %{context | match_operator?: true})

    "Interpreter.matchOperator(#{right}, #{left}, vars)"
  end

  def encode(%IR.MatchPlaceholder{}, _context) do
    "Type.matchPlaceholder()"
  end

  def encode(%IR.ModuleAttributeOperator{name: name}, _context) do
    encode_var_value("@#{name}", false)
  end

  def encode(%IR.ModuleDefinition{module: module, body: body}, context) do
    class = encode_as_class_name(module.value)

    body.expressions
    |> aggregate_module_functions()
    |> Enum.reduce([], fn {{function, arity}, clauses}, acc ->
      clauses_js = encode_as_array(clauses, context)

      [
        ~s/Interpreter.defineElixirFunction("#{class}", "#{function}", #{arity}, #{clauses_js})/
        | acc
      ]
    end)
    |> Enum.reverse()
    |> Enum.join("\n\n")
  end

  def encode(%IR.PinOperator{name: name}, _context) do
    "vars.#{name}"
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
        %IR.RemoteFunctionCall{module: expr, function: function, args: args},
        context
      ) do
    callable = encode(expr, context)
    encode_function_call(callable, function, args, context)
  end

  def encode(%IR.StringType{value: value}, _context) do
    encode_primitive_type(:bitstring, value, true)
  end

  # TODO: implement
  def encode(%IR.Try{}, _context) do
    "Interpreter.try()"
  end

  def encode(%IR.TupleType{data: data}, context) do
    data_str = encode_as_array(data, context)
    "Type.tuple(#{data_str})"
  end

  def encode(%IR.Variable{name: name}, %{pattern?: true}) do
    name_str = encode_as_string(name, true)
    "Type.variablePattern(#{name_str})"
  end

  def encode(%IR.Variable{name: name}, %{pattern?: false, use_vars_snapshot?: use_vars_snapshot?}) do
    encode_var_value(name, use_vars_snapshot?)
  end

  @doc """
  Prints debug info for intercepted encode/2 calls.
  """
  @spec debug(
          {module, atom, list(IR.t() | Context.t())},
          String.t() | %{__struct__: FunctionClauseError},
          integer
        ) :: :ok
  def debug({_module, _function, [ir, context] = _args}, result, _start_timestamp) do
    # credo:disable-for-lines:10 /Credo.Check.Refactor.IoPuts|Credo.Check.Warning.IoInspect/
    IO.puts("\nENCODE..................................\n")
    IO.puts("ir")
    IO.inspect(ir)
    IO.puts("")
    IO.puts("context")
    IO.inspect(context)
    IO.puts("")
    IO.puts("result")
    IO.inspect(result)
    IO.puts("\n........................................\n")
  end

  @doc """
  Encodes an Elixir alias as a class name.

  - This function converts the `alias_atom` to a string using `to_string/1`.
  - If the resulting `alias_str` starts with a lowercase letter, it prefixes it with `"Erlang."`.
  - Finally, any dots (`.`) in the `prefixed_alias_str` are replaced with underscores (`_`).
  - If :erlang is given as input, it returns `"Erlang"`.

  ## Parameters

  - `alias_atom` - The Elixir alias to be encoded as a class name.

  ## Returns

  The encoded class name.

  ## Examples

      iex> encode_as_class_name(Aaa.Bbb.Ccc)
      "Elixir_Aaa_Bbb_Ccc"

      iex> encode_as_class_name(:mymodule)
      "Erlang_Mymodule"

      iex> encode_as_class_name(:erlang)
      "Erlang"
  """
  @spec encode_as_class_name(module | atom) :: String.t()
  def encode_as_class_name(alias_atom)

  def encode_as_class_name(:erlang), do: "Erlang"

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

  # TODO: consider - remove
  @doc """
  Escapes chacters which are not allowed in JS identifiers with their Unicode code points.

  Although $ (dollar sign) character is allowed in JS identifiers, we escape it as well,
  because it is used as a marker for other escaped characters.

  ## Examples

      iex> escape_js_identifier("my_fun?")
      "my_fun$263"
  """
  @spec escape_js_identifier(String.t()) :: String.t()
  def escape_js_identifier(identifier) do
    identifier
    |> String.to_charlist()
    |> Enum.map_join("", fn code_point ->
      if allowed_in_js_identifier?(code_point) do
        to_string([code_point])
      else
        digit_count = IntegerUtils.count_digits(code_point)
        "$#{digit_count}#{code_point}"
      end
    end)
  end

  defp aggregate_module_functions(exprs) do
    exprs
    |> Enum.reduce(%{}, fn
      %IR.FunctionDefinition{name: name, arity: arity, clause: clause}, acc ->
        key = {name, arity}

        if acc[key] do
          %{acc | key => [clause | acc[key]]}
        else
          Map.put(acc, key, [clause])
        end

      _expr, acc ->
        acc
    end)
    |> Enum.map(fn {key, value} -> {key, Enum.reverse(value)} end)
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

  defp encode_as_array(data, context, encoder \\ &encode/2) do
    data
    |> Enum.map_join(", ", &encoder.(&1, context))
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

  defp encode_bitstring_segments(segments, context) do
    Enum.map_join(segments, ", ", &encode(&1, context))
  end

  defp encode_closure(nil, _context), do: "null"

  defp encode_closure(ir, context) do
    "(vars) => #{encode(ir, context)}"
  end

  defp encode_function_call(callable, function, args, context) do
    arity = Enum.count(args)
    args_js = Enum.map_join(args, ", ", &encode(&1, context))

    "#{callable}[\"#{function}/#{arity}\"](#{args_js})"
  end

  defp encode_primitive_type(type, value, as_string)

  defp encode_primitive_type(type, value, true) do
    value_str = encode_as_string(value, true)
    encode_primitive_type(type, value_str, false)
  end

  defp encode_primitive_type(type, value, false) do
    "Type.#{type}(#{value})"
  end

  defp encode_var_value(name, use_vars_snapshot?)

  defp encode_var_value(name, true) do
    "vars.__snapshot__.#{escape_var_name(name)}"
  end

  defp encode_var_value(name, false) do
    "vars.#{escape_var_name(name)}"
  end

  defp escape_var_name(name) do
    name
    |> to_string()
    |> escape_js_identifier()
  end
end
