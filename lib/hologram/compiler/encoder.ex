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
    clauses
    |> encode_as_array(context)
    |> then(&"Type.anonymousFunction(#{arity}, #{&1}, vars)")
  end

  def encode(%IR.AtomType{value: value}, _context) do
    encode_primitive_type(:atom, value, true)
  end

  # See: https://hexdocs.pm/elixir/1.14.5/Kernel.SpecialForms.html#<<>>/1
  def encode(
        %IR.BitstringSegment{value: %IR.StringType{value: value}, modifiers: modifiers},
        context
      ) do
    :string
    |> encode_primitive_type(value, true)
    |> encode_bitstring_segment(modifiers, context)
  end

  # See: https://hexdocs.pm/elixir/1.14.5/Kernel.SpecialForms.html#<<>>/1
  def encode(%IR.BitstringSegment{value: value, modifiers: modifiers}, context) do
    value
    |> encode(context)
    |> encode_bitstring_segment(modifiers, context)
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
    exprs
    |> then(fn
      [] -> [%IR.AtomType{value: nil}]
      exprs -> exprs
    end)
    |> then(fn exprs ->
      expr_count = Enum.count(exprs)

      exprs
      |> Enum.with_index()
      |> Enum.map_join("", &map_block_expr(&1, context, expr_count))
      |> then(&StringUtils.wrap(&1, "{", "\n}"))
    end)
  end

  def encode(%IR.Case{condition: condition, clauses: clauses}, context) do
    condition_js =
      case condition do
        %IR.Block{} = block -> encode_closure(block, context)
        expr -> encode(expr, context)
      end

    clauses_js = encode_as_array(clauses, context)
    "Interpreter.case(#{condition_js}, #{clauses_js}, vars)"
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
    clauses_ir
    |> encode_as_array(context)
    |> then(&StringUtils.wrap(&1, "Interpreter.cond(", ")"))
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
    "Interpreter.dotOperator(#{encode(left, context)}, #{encode(right, context)})"
  end

  def encode(%IR.FloatType{value: value}, _context) do
    encode_primitive_type(:float, value, false)
  end

  def encode(%IR.FunctionClause{} = clause, context) do
    params_array = encode_as_array(clause.params, %{context | pattern?: true})
    params_closure = "(vars) => #{params_array}"
    guards = encode_as_array(clause.guards, context, &encode_closure/2)
    body = encode_closure(clause.body, context)
    "{params: #{params_closure}, guards: #{guards}, body: #{body}}"
  end

  def encode(%IR.IntegerType{value: value}, _context) do
    encode_primitive_type(:integer, "#{value}n", false)
  end

  def encode(%IR.ListType{data: data}, context) do
    data
    |> encode_as_array(context)
    |> then(&StringUtils.wrap(&1, "Type.list(", ")"))
  end

  def encode(%IR.LocalFunctionCall{function: function, args: args}, %{module: module} = context) do
    module_ir = %IR.AtomType{value: module}
    encode_named_function_call(module_ir, function, args, context)
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
    |> Enum.map_join("\n\n", fn {{function, arity}, clauses} ->
      clauses_js = encode_as_array(clauses, context)
      ~s/Interpreter.defineElixirFunction("#{class}", "#{function}", #{arity}, #{clauses_js});/
    end)
  end

  def encode(%IR.PIDType{value: value}, _context) do
    encode_primitive_type(:pid, value, true)
  end

  def encode(%IR.PinOperator{name: name}, _context) do
    "vars.#{name}"
  end

  def encode(%IR.PortType{value: value}, _context) do
    encode_primitive_type(:port, value, true)
  end

  def encode(%IR.ReferenceType{value: value}, _context) do
    encode_primitive_type(:reference, value, true)
  end

  def encode(%IR.RemoteFunctionCall{module: module, function: function, args: args}, context) do
    encode_named_function_call(module, function, args, context)
  end

  def encode(%IR.StringType{value: value}, _context) do
    encode_primitive_type(:bitstring, value, true)
  end

  # TODO: catch_clauses, else_clauses, after_block
  def encode(%IR.Try{} = ir, context) do
    body_js = encode_closure(ir.body, context)
    rescue_clauses_js = encode_as_array(ir.rescue_clauses, context)

    "Interpreter.try(#{body_js}, #{rescue_clauses_js}, [], [], null, vars)"
  end

  def encode(%IR.TryRescueClause{} = ir, context) do
    variable_js =
      if ir.variable do
        encode(ir.variable, %{context | pattern?: true})
      else
        "null"
      end

    modules_js = encode_as_array(ir.modules, context)
    body_js = encode_closure(ir.body, context)

    "{variable: #{variable_js}, modules: #{modules_js}, body: #{body_js}}"
  end

  def encode(%IR.TupleType{data: data}, context) do
    data
    |> encode_as_array(context)
    |> then(&StringUtils.wrap(&1, "Type.tuple(", ")"))
  end

  def encode(%IR.Variable{name: name}, %{pattern?: true}) do
    name
    |> encode_as_string()
    |> then(&StringUtils.wrap(&1, "Type.variablePattern(", ")"))
  end

  def encode(%IR.Variable{name: name}, %{pattern?: false, use_vars_snapshot?: use_vars_snapshot?}) do
    encode_var_value(name, use_vars_snapshot?)
  end

  # TODO: finish implementing
  def encode(%IR.With{}, _context) do
    "Interpreter.with()"
  end

  defp map_block_expr({expr, idx}, context, expr_count) do
    # If the expression contains variables that are used both as patterns (in match operator)
    # and as values (value access), then we need to take a snapshot of these variables
    # before evaluating the expression, and then use that snapshot for accessing variable values.

    expr
    |> Analyzer.analyze()
    |> then(&MapSet.intersection(&1.var_patterns, &1.var_values))
    |> map_block_expr(context, idx, expr_count, expr)
  end

  @empty_map_set MapSet.new()
  defp map_block_expr(map_set, context, idx, expr_count, expr) when map_set == @empty_map_set do
    map_block_expr("", context, idx, expr_count, expr)
  end

  defp map_block_expr(map_set, context, idx, expr_count, expr) when is_struct(map_set, MapSet) do
    output = "\nInterpreter.takeVarsSnapshot(vars);"
    map_block_expr(output, %{context | use_vars_snapshot?: true}, idx, expr_count, expr)
  end

  defp map_block_expr(output, context, idx, expr_count, expr) when idx == expr_count - 1 do
    output
    |> StringUtils.append("\nreturn ")
    |> do_map_block_expr(context, expr)
  end

  defp map_block_expr(output, context, _idx, _expr_count, expr) do
    output
    |> StringUtils.append("\n")
    |> do_map_block_expr(context, expr)
  end

  defp do_map_block_expr(output, context, expr) do
    expr
    |> encode(context)
    |> StringUtils.wrap(output, ";")
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
  Encodes Elixir or Erlang alias as JavaScript class name.

  ## Examples

      iex> encode_as_class_name(Aaa.Bbb.Ccc)
      "Elixir_Aaa_Bbb_Ccc"

      iex> encode_as_class_name(:erlang)
      "Erlang"
      
      iex> encode_as_class_name(:aaa_bbb)
      "Erlang_Aaa_Bbb"      
  """
  @spec encode_as_class_name(module | atom) :: String.t()
  def encode_as_class_name(alias_atom)

  def encode_as_class_name(:erlang), do: "Erlang"

  def encode_as_class_name(alias_atom) do
    alias_atom
    |> to_string()
    |> String.split([".", "_"])
    |> then(fn
      ["Elixir" | _rest] = module_segments -> module_segments
      module_segments -> ["Erlang" | module_segments]
    end)
    |> Enum.map_join("_", &:string.titlecase/1)
  end

  @doc """
  Encodes Elixir data chunk into JavaScript.
  """
  @spec encode_term(any) :: String.t()
  def encode_term(term) do
    term
    |> IR.for_term()
    |> encode(%Context{})
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
    |> Enum.map_join("", &escape_js_code_point/1)
  end

  @spec escape_js_code_point(non_neg_integer) :: String.t()
  defp escape_js_code_point(code_point)
       when code_point == ?_ or code_point in ?0..?9 or code_point in ?A..?Z or
              code_point in ?a..?z do
    to_string([code_point])
  end

  defp escape_js_code_point(code_point) when is_integer(code_point) do
    code_point
    |> IntegerUtils.count_digits()
    |> then(&"$#{&1}#{code_point}")
  end

  defp aggregate_module_functions(exprs) do
    List.foldr(exprs, %{}, fn
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
  end

  defp encode_as_array(data, context, encoder \\ &encode/2) do
    data
    |> Enum.map_join(", ", &encoder.(&1, context))
    |> StringUtils.wrap("[", "]")
  end

  defp encode_as_string(value) when is_atom(value) and value not in [false, nil, true] do
    value
    |> to_string()
    |> encode_as_string()
  end

  defp encode_as_string(value) when is_binary(value) do
    inspect(value)
  end

  defp encode_as_string(value) do
    value
    |> inspect()
    |> StringUtils.unwrap("#PID<", ">")
    |> StringUtils.unwrap("#Port<", ">")
    |> StringUtils.unwrap("#Reference<", ">")
    |> encode_as_string()
  end

  defp encode_bitstring_modifier({:size, size}, context) do
    size
    |> encode(context)
    |> StringUtils.prepend("size: ")
  end

  defp encode_bitstring_modifier({:unit, unit}, _context) do
    unit
    |> Integer.to_string()
    |> StringUtils.wrap("unit: ", "n")
  end

  defp encode_bitstring_modifier({name, value}, _context) do
    ~s(#{name}: "#{value}")
  end

  defp encode_bitstring_segment(value_str, modifiers, context) do
    modifiers
    |> Enum.map_join(", ", &encode_bitstring_modifier(&1, context))
    |> StringUtils.wrap("{", "}")
    |> then(&"Type.bitstringSegment(#{value_str}, #{&1})")
  end

  defp encode_bitstring_segments(segments, context) do
    Enum.map_join(segments, ", ", &encode(&1, context))
  end

  defp encode_closure(nil, _context), do: "null"

  defp encode_closure(ir, context) do
    ir
    |> encode(context)
    |> StringUtils.prepend("(vars) => ")
  end

  defp encode_named_function_call(%IR.AtomType{} = module, function, args, context) do
    class = encode_as_class_name(module.value)
    arity = Enum.count(args)
    args_js = Enum.map_join(args, ", ", &encode(&1, context))
    "#{class}[\"#{function}/#{arity}\"](#{args_js})"
  end

  defp encode_named_function_call(module, function, args, context) do
    module_js = encode(module, context)
    function_arity_str = "#{function}/#{Enum.count(args)}"
    args_js = encode_as_array(args, context)
    "Interpreter.callNamedFunction(#{module_js}, \"#{function_arity_str}\", #{args_js})"
  end

  defp encode_primitive_type(type, value, as_string)

  defp encode_primitive_type(type, value, true) do
    value
    |> encode_as_string()
    |> then(&encode_primitive_type(type, &1, false))
  end

  defp encode_primitive_type(type, value, false) do
    "Type.#{type}(#{value})"
  end

  defp encode_var_value(name, use_vars_snapshot?)

  defp encode_var_value(name, true) do
    name
    |> escape_var_name()
    |> StringUtils.prepend("vars.__snapshot__.")
  end

  defp encode_var_value(name, false) do
    name
    |> escape_var_name()
    |> StringUtils.prepend("vars.")
  end

  defp escape_var_name(name) do
    name
    |> to_string()
    |> escape_js_identifier()
  end
end
