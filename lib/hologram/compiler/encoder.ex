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
        expr_js = encode(expr, context)

        last_expr? = idx == expr_count - 1
        has_match_operator? = has_match_operator?(expr)

        encode_block_expr(expr_js, last_expr?, has_match_operator?)
      end)

    "{#{body}\n}"
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
    clauses_js = encode_as_array(clauses_ir, context)
    "Interpreter.cond(#{clauses_js}, vars)"
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
    data_str = encode_as_array(data, context)
    "Type.list(#{data_str})"
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
    encode_var_value("@#{name}")
  end

  def encode(%IR.ModuleDefinition{module: module, body: body}, context) do
    class = encode_as_class_name(module.value)

    body.expressions
    |> aggregate_module_functions()
    |> Enum.reduce([], fn {{function, arity}, clauses}, acc ->
      clauses_js = encode_as_array(clauses, context)

      [
        ~s/Interpreter.defineElixirFunction("#{class}", "#{function}", #{arity}, #{clauses_js});/
        | acc
      ]
    end)
    |> Enum.reverse()
    |> Enum.join("\n\n")
  end

  # See info about the internal structure of PIDs: https://stackoverflow.com/a/262179/13040586
  def encode(%IR.PIDType{value: pid}, context) do
    segments =
      pid
      |> :erlang.pid_to_list()
      |> List.delete_at(0)
      |> List.delete_at(-1)
      |> to_string()
      |> String.split(".")
      |> Enum.map(&IntegerUtils.parse!/1)

    encoded_node = encode_as_string(node(pid), true)

    integer_encoder = fn integer, _context -> to_string(integer) end
    encoded_segments = encode_as_array(segments, context, integer_encoder)

    "Type.pid(#{encoded_node}, #{encoded_segments})"
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

  def encode(
        %IR.RemoteFunctionCall{
          module: module,
          function: function,
          args: args
        },
        context
      ) do
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
    data_js = encode_as_array(data, context)
    "Type.tuple(#{data_js})"
  end

  def encode(%IR.Variable{name: name}, %{pattern?: true}) do
    name_js = encode_as_string(name, true)
    "Type.variablePattern(#{name_js})"
  end

  def encode(%IR.Variable{name: name}, %{pattern?: false}) do
    encode_var_value(name)
  end

  # TODO: finish implementing
  def encode(%IR.With{}, _context) do
    "Interpreter.with()"
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
    module_segments =
      alias_atom
      |> to_string()
      |> String.split([".", "_"])

    class_segments =
      if hd(module_segments) == "Elixir" do
        module_segments
      else
        ["Erlang" | module_segments]
      end

    Enum.map_join(class_segments, "_", &:string.titlecase/1)
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

  defp encode_as_array(data, context, encoder \\ &encode/2) do
    data
    |> Enum.map_join(", ", &encoder.(&1, context))
    |> StringUtils.wrap("[", "]")
  end

  defp encode_as_string(value, wrap)

  defp encode_as_string(nil, false) do
    "nil"
  end

  defp encode_as_string(value, false) when is_port(value) do
    value
    |> :erlang.port_to_list()
    |> Enum.drop(6)
    |> List.delete_at(-1)
    |> to_string()
  end

  defp encode_as_string(value, false) when is_reference(value) do
    value
    |> :erlang.ref_to_list()
    |> Enum.drop(5)
    |> List.delete_at(-1)
    |> to_string()
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

  defp encode_block_expr(expr_js, last_expr?, has_match_operator?)

  defp encode_block_expr(expr_js, true, true) do
    """

    window.__hologramReturn__ = #{expr_js};
    Interpreter.updateVarsToMatchedValues(vars);
    return window.__hologramReturn__;\
    """
  end

  defp encode_block_expr(expr_js, true, false) do
    "\nreturn #{expr_js};"
  end

  defp encode_block_expr(expr_js, false, true) do
    """

    #{expr_js};
    Interpreter.updateVarsToMatchedValues(vars);\
    """
  end

  defp encode_block_expr(expr_js, false, false) do
    "\n#{expr_js};"
  end

  defp encode_closure(nil, _context), do: "null"

  defp encode_closure(ir, context) do
    "(vars) => #{encode(ir, context)}"
  end

  defp encode_named_function_call(%IR.AtomType{value: :erlang}, :andalso, [left, right], context) do
    left_js = encode_closure(left, context)
    right_js = encode_closure(right, context)

    "Erlang[\"andalso/2\"](#{left_js}, #{right_js}, vars)"
  end

  defp encode_named_function_call(%IR.AtomType{value: :erlang}, :orelse, [left, right], context) do
    left_js = encode_closure(left, context)
    right_js = encode_closure(right, context)

    "Erlang[\"orelse/2\"](#{left_js}, #{right_js}, vars)"
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
    value_str = encode_as_string(value, true)
    encode_primitive_type(type, value_str, false)
  end

  defp encode_primitive_type(type, value, false) do
    "Type.#{type}(#{value})"
  end

  defp encode_var_value(var_name) do
    var_name = to_string(var_name)

    if String.match?(var_name, ~r/[^a-zA-Z0-9_]+/) do
      ~s'vars["#{var_name}"]'
    else
      "vars.#{var_name}"
    end
  end

  defp has_match_operator?(ir)

  defp has_match_operator?(%IR.MatchOperator{}), do: true

  defp has_match_operator?(ir) when is_list(ir) do
    Enum.any?(ir, &has_match_operator?/1)
  end

  defp has_match_operator?(ir) when is_tuple(ir) do
    ir
    |> Tuple.to_list()
    |> has_match_operator?()
  end

  defp has_match_operator?(%_struct{} = ir) do
    ir
    |> Map.from_struct()
    |> has_match_operator?()
  end

  defp has_match_operator?(ir) when is_map(ir) do
    Enum.any?(ir, fn {key, value} -> has_match_operator?(key) || has_match_operator?(value) end)
  end

  defp has_match_operator?(_ast), do: false
end
