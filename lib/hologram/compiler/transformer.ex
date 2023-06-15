defmodule Hologram.Compiler.Transformer do
  if Application.compile_env(:hologram, :debug_transformer) do
    use Interceptor.Annotated,
      config: %{
        {Hologram.Compiler.Transformer, :transform, 2} => [
          on_success: {Hologram.Compiler.Transformer, :debug, 3},
          on_error: {Hologram.Compiler.Transformer, :debug, 3}
        ]
      }
  end

  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR

  @doc """
  Transforms Elixir AST to Hologram IR.

  ## Examples

      iex> ast = quote do {1, 2, 3} end
      {:{}, [], [1, 2, 3]}
      iex> transform(ast)
      %IR.TupleType{data: [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 2}, %IR.IntegerType{value: 3}]}
  """
  @intercept true
  @spec transform(AST.t(), Context.t()) :: IR.t()
  def transform(ast, context)

  def transform({{:., _meta_2, [function]}, _meta_1, args}, context) do
    %IR.AnonymousFunctionCall{
      function: transform(function, context),
      args: transform_list(args, context)
    }
  end

  def transform({:fn, _meta, clauses}, context) do
    clauses_ir = Enum.map(clauses, &transform_anonymous_function_clause(&1, context))

    arity =
      clauses_ir
      |> hd()
      |> Map.fetch!(:params)
      |> Enum.count()

    %IR.AnonymousFunctionType{
      arity: arity,
      clauses: clauses_ir
    }
  end

  # Local function capture
  def transform({:&, meta, [{:/, meta, [{function, meta, nil}, arity]}]}, context) do
    transform_function_capture(function, arity, meta, context)
  end

  # Remote function capture
  def transform(
        {:&, meta, [{:/, meta, [{function, [{:no_parens, true} | meta], []}, arity]}]},
        context
      ) do
    transform_function_capture(function, arity, meta, context)
  end

  # Partially applied function arg placeholder
  # sobelow_skip ["DOS.BinToAtom"]
  def transform({:&, meta, [index]}, context) when is_integer(index) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    ast = {:"holo_arg_#{index}__", meta, nil}
    transform(ast, context)
  end

  # Partially applied anonymous function
  def transform({:&, meta, body}, context) do
    arity = determine_partially_applied_function_arity(body, 0)
    args = build_function_capture_args(arity, meta)
    ast = {:fn, meta, [{:->, meta, [args, {:__block__, [], body}]}]}

    transform(ast, context)
  end

  def transform(value, _context) when is_atom(value) do
    %IR.AtomType{value: value}
  end

  def transform({:<<>>, _meta, segments}, context) do
    segments_ir =
      segments
      |> Enum.map(&transform_bitstring_segment(&1, context))
      |> flatten_bitstring_segments()

    %IR.BitstringType{segments: segments_ir}
  end

  def transform({:__block__, _meta, exprs}, context) do
    exprs_ir = Enum.map(exprs, &transform(&1, context))
    %IR.Block{expressions: exprs_ir}
  end

  def transform({:case, _meta, [condition, [do: clauses]]}, context) do
    condition_ir = transform(condition, context)
    clauses_ir = Enum.map(clauses, &build_case_clause_ir(&1, context))

    %IR.CaseExpression{
      condition: condition_ir,
      clauses: clauses_ir
    }
  end

  def transform({:for, _meta, parts}, context) do
    initial_acc = %{
      generators: [],
      filters: [],
      collectable: %IR.ListType{data: []},
      unique: %IR.AtomType{value: false},
      mapper: nil
    }

    %{
      generators: generators,
      filters: filters,
      collectable: collectable,
      unique: unique,
      mapper: mapper
    } =
      Enum.reduce(
        parts,
        initial_acc,
        &transform_comprehension_part(&1, &2, context)
      )

    %IR.Comprehension{
      generators: Enum.reverse(generators),
      filters: Enum.reverse(filters),
      collectable: collectable,
      unique: unique,
      mapper: mapper
    }
  end

  def transform({:cond, _meta, [[do: clauses]]}, context) do
    clauses_ir = Enum.map(clauses, &build_cond_clause_ir(&1, context))

    %IR.CondExpression{clauses: clauses_ir}
  end

  def transform([{:|, _meta, [head, tail]}], context) do
    %IR.ConsOperator{
      head: transform(head, context),
      tail: transform(tail, context)
    }
  end

  def transform(
        {{:., _meta_2, [{marker, _meta_3, nil} = left, right]}, [{:no_parens, true} | _meta_1],
         []},
        context
      )
      when marker != :__aliases__ do
    %IR.DotOperator{
      left: transform(left, context),
      right: transform(right, context)
    }
  end

  def transform(value, _context) when is_float(value) do
    %IR.FloatType{value: value}
  end

  def transform({marker, _meta_1, [{name, _meta_2, params}, [do: body]]}, context)
      when marker in [:def, :defp] do
    params =
      params
      |> List.wrap()
      |> transform_list(context)

    visibility = if marker == :def, do: :public, else: :private

    %IR.FunctionDefinition{
      name: name,
      arity: Enum.count(params),
      params: params,
      body: transform(body, context),
      visibility: visibility
    }
  end

  def transform(value, _context) when is_integer(value) do
    %IR.IntegerType{value: value}
  end

  def transform(data, context) when is_list(data) do
    %IR.ListType{data: transform_list(data, context)}
  end

  def transform({:defmacro, _meta, _args}, _context) do
    %IR.IgnoredExpression{type: :public_macro_definition}
  end

  def transform({:defmacrop, _meta, _args}, _context) do
    %IR.IgnoredExpression{type: :private_macro_definition}
  end

  # Map with cons operator is transformed to Map.merge/2 remote function call.
  def transform({:%{}, _meta_1, [{:|, _meta_2, [map, data]}]}, context) do
    %IR.RemoteFunctionCall{
      module: %IR.AtomType{value: Map},
      function: :merge,
      args: [
        transform(map, context),
        %IR.MapType{data: transform_list(data, context)}
      ]
    }
  end

  def transform({:%{}, _meta, data}, context) do
    data_ir =
      Enum.map(data, fn {key, value} ->
        {transform(key, context), transform(value, context)}
      end)

    %IR.MapType{data: data_ir}
  end

  def transform({:=, _meta, [left, right]}, context) do
    %IR.MatchOperator{
      left: transform(left, %{context | pattern?: true}),
      right: transform(right, context)
    }
  end

  # Module is transformed to atom type.
  def transform({:__aliases__, meta, [:"Elixir" | alias_segs]}, context) do
    transform({:__aliases__, meta, alias_segs}, context)
  end

  # Module is transformed to atom type.
  def transform({:__aliases__, _meta, alias_segs}, context) do
    alias_segs
    |> Helpers.module()
    |> transform(context)
  end

  # Module attributes are expanded by beam_file package, but we still need them for templates.
  def transform({:@, _meta_1, [{name, _meta_2, expr}]}, _context) when not is_list(expr) do
    %IR.ModuleAttributeOperator{name: name}
  end

  def transform({:defmodule, _meta, [module, [do: body]]}, context) do
    %IR.ModuleDefinition{
      module: transform(module, context),
      body: transform(body, context)
    }
  end

  def transform({:^, _meta_1, [{name, _meta_2, _args}]}, _context) do
    %IR.PinOperator{name: name}
  end

  def transform(value, _context) when is_binary(value) do
    %IR.StringType{value: value}
  end

  # Struct with cons operator is transformed to nested Map.merge/2 and __struct__/1 remote function calls.
  def transform({:%, _meta_1, [module, {:%{}, _meta_2, [{:|, _meta_3, [map, data]}]}]}, context) do
    %IR.RemoteFunctionCall{
      module: %IR.AtomType{value: Map},
      function: :merge,
      args: [
        transform(map, context),
        %IR.RemoteFunctionCall{
          module: transform(module, context),
          function: :__struct__,
          args: [transform(data, context)]
        }
      ]
    }
  end

  # Struct without cons operator inside a pattern is transformed into map IR in place.
  def transform({:%, _meta, [module, {:%{}, meta, data}]}, %Context{pattern?: true} = context) do
    new_data = [{:__struct__, module} | data]
    transform({:%{}, meta, new_data}, context)
  end

  # Struct without cons operator not in a pattern is transformed to __struct__/1 remote function call.
  def transform(
        {:%, _meta_1, [module, {:%{}, _meta_2, data}]},
        %Context{pattern?: false} = context
      ) do
    %IR.RemoteFunctionCall{
      module: transform(module, context),
      function: :__struct__,
      args: [transform(data, context)]
    }
  end

  def transform({:{}, _meta, data}, context) do
    build_tuple_type_ir(data, context)
  end

  def transform({_el_1, _el_2} = data, context) do
    data
    |> Tuple.to_list()
    |> build_tuple_type_ir(context)
  end

  # --- PRESERVE ORDER (BEGIN) ---

  def transform({{:., _meta_2, [module, function]}, _meta_1, args}, context) do
    %IR.RemoteFunctionCall{
      module: transform(module, context),
      function: function,
      args: transform_list(args, context)
    }
  end

  def transform({name, _meta, nil}, _context) when is_atom(name) do
    case to_string(name) do
      "_" <> _rest ->
        %IR.MatchPlaceholder{}

      _fallback ->
        %IR.Variable{name: name}
    end
  end

  def transform({function, _meta, args}, context) when is_atom(function) and is_list(args) do
    %IR.LocalFunctionCall{
      function: function,
      args: transform_list(args, context)
    }
  end

  # --- PRESERVE ORDER (END) ---

  @doc """
  Prints debug info for intercepted transform/2 calls.
  """
  @spec debug(
          {module, atom, list(AST.t() | Context.t())},
          IR.t() | %{__struct__: FunctionClauseError},
          integer
        ) :: :ok
  def debug({_module, _function, [ast, context] = _args}, result, _start_timestamp) do
    # credo:disable-for-lines:10 /Credo.Check.Refactor.IoPuts|Credo.Check.Warning.IoInspect/
    IO.puts("\nTRANSFORM...............................\n")
    IO.puts("ast")
    IO.inspect(ast)
    IO.puts("")
    IO.puts("context")
    IO.inspect(context)
    IO.puts("")
    IO.puts("result")
    IO.inspect(result)
    IO.puts("\n........................................\n")
  end

  defp accumulate_comprehension_generator(acc, enumerable, match, guard, context) do
    guard_ir =
      if guard do
        transform(guard, context)
      else
        nil
      end

    generator = %IR.ComprehensionGenerator{
      enumerable: transform(enumerable, context),
      match: transform(match, context),
      guard: guard_ir
    }

    %{acc | generators: [generator | acc.generators]}
  end

  defp build_case_clause_ir({:->, _meta_1, [[{:when, _meta_2, [head, guard]}], body]}, context) do
    %IR.CaseClause{
      head: transform(head, context),
      guard: transform(guard, context),
      body: transform(body, context)
    }
  end

  defp build_case_clause_ir({:->, _meta, [[head], body]}, context) do
    %IR.CaseClause{
      head: transform(head, context),
      guard: nil,
      body: transform(body, context)
    }
  end

  defp build_cond_clause_ir({:->, _meta, [[condition], body]}, context) do
    %IR.CondClause{
      condition: transform(condition, context),
      body: transform(body, context)
    }
  end

  # sobelow_skip ["DOS.BinToAtom"]
  defp build_function_capture_args(arity, meta) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Enum.map(1..arity, &{:"holo_arg_#{&1}__", meta, nil})
  end

  defp build_tuple_type_ir(data, context) do
    %IR.TupleType{data: transform_list(data, context)}
  end

  defp determine_partially_applied_function_arity({:&, _meta, [index]}, arity)
       when is_integer(index) and index > arity,
       do: index

  defp determine_partially_applied_function_arity(ast, arity) when is_list(ast) do
    Enum.reduce(ast, arity, &determine_partially_applied_function_arity/2)
  end

  defp determine_partially_applied_function_arity({_marker, _meta, children}, arity)
       when is_list(children) do
    determine_partially_applied_function_arity(children, arity)
  end

  defp determine_partially_applied_function_arity(_ast, arity), do: arity

  defp flatten_bitstring_segments(segments) do
    segments
    |> Enum.reduce([], fn segment, acc ->
      case segment do
        %IR.BitstringSegment{value: %IR.BitstringType{segments: nested_segments}} ->
          Enum.reverse(nested_segments) ++ acc

        segment ->
          [segment | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp maybe_add_default_bitstring_type_modifier(modifiers, value) do
    if Keyword.has_key?(modifiers, :type) do
      modifiers
    else
      case value do
        %IR.FloatType{} ->
          [{:type, :float} | modifiers]

        %IR.StringType{} ->
          [{:type, :utf8} | modifiers]

        _value ->
          [{:type, :integer} | modifiers]
      end
    end
  end

  defp transform_anonymous_function_clause(
         {:->, _meta_1, [[{:when, _meta_2, params_and_guard}], body]},
         context
       ) do
    {guard, params} = List.pop_at(params_and_guard, -1)

    %IR.AnonymousFunctionClause{
      params: transform_list(params, context),
      guard: transform(guard, context),
      body: transform(body, context)
    }
  end

  defp transform_anonymous_function_clause({:->, _meta, [params, body]}, context) do
    %IR.AnonymousFunctionClause{
      params: transform_list(params, context),
      guard: nil,
      body: transform(body, context)
    }
  end

  defp transform_bitstring_modifiers({:-, _meta, [left, right]}, context, modifiers) do
    new_modifiers = transform_bitstring_modifiers(left, context, modifiers)
    transform_bitstring_modifiers(right, context, new_modifiers)
  end

  defp transform_bitstring_modifiers({:*, _meta, [size, unit]}, context, modifiers) do
    size = transform(size, context)
    [{:unit, unit} | [{:size, size} | modifiers]]
  end

  defp transform_bitstring_modifiers({:big, _meta, nil}, _context, modifiers) do
    [{:endianness, :big} | modifiers]
  end

  defp transform_bitstring_modifiers({:binary, _meta, nil}, _context, modifiers) do
    [{:type, :binary} | modifiers]
  end

  defp transform_bitstring_modifiers({:bits, _meta, nil}, _context, modifiers) do
    [{:type, :bitstring} | modifiers]
  end

  defp transform_bitstring_modifiers({:bitstring, _meta, nil}, _context, modifiers) do
    [{:type, :bitstring} | modifiers]
  end

  defp transform_bitstring_modifiers({:bytes, _meta, nil}, _context, modifiers) do
    [{:type, :binary} | modifiers]
  end

  defp transform_bitstring_modifiers({:float, _meta, nil}, _context, modifiers) do
    [{:type, :float} | modifiers]
  end

  defp transform_bitstring_modifiers({:integer, _meta, nil}, _context, modifiers) do
    [{:type, :integer} | modifiers]
  end

  defp transform_bitstring_modifiers({:little, _meta, nil}, _context, modifiers) do
    [{:endianness, :little} | modifiers]
  end

  defp transform_bitstring_modifiers({:native, _meta, nil}, _context, modifiers) do
    [{:endianness, :native} | modifiers]
  end

  defp transform_bitstring_modifiers({:signed, _meta, nil}, _context, modifiers) do
    [{:signedness, :signed} | modifiers]
  end

  defp transform_bitstring_modifiers({:size, _meta, [size]}, context, modifiers) do
    [{:size, transform(size, context)} | modifiers]
  end

  defp transform_bitstring_modifiers({:unit, _meta, [unit]}, _context, modifiers) do
    [{:unit, unit} | modifiers]
  end

  defp transform_bitstring_modifiers({:unsigned, _meta, nil}, _context, modifiers) do
    [{:signedness, :unsigned} | modifiers]
  end

  defp transform_bitstring_modifiers({:utf8, _meta, nil}, _context, modifiers) do
    [{:type, :utf8} | modifiers]
  end

  defp transform_bitstring_modifiers({:utf16, _meta, nil}, _context, modifiers) do
    [{:type, :utf16} | modifiers]
  end

  defp transform_bitstring_modifiers({:utf32, _meta, nil}, _context, modifiers) do
    [{:type, :utf32} | modifiers]
  end

  defp transform_bitstring_modifiers(size, context, modifiers) do
    [{:size, transform(size, context)} | modifiers]
  end

  defp transform_bitstring_segment({:"::", _meta, [left, right]}, context) do
    value = transform(left, context)

    modifiers =
      right
      |> transform_bitstring_modifiers(context, [])
      |> maybe_add_default_bitstring_type_modifier(value)

    %IR.BitstringSegment{value: value, modifiers: modifiers}
  end

  defp transform_bitstring_segment(ast, context) do
    value = transform(ast, context)
    modifiers = maybe_add_default_bitstring_type_modifier([], value)

    %IR.BitstringSegment{value: value, modifiers: modifiers}
  end

  defp transform_comprehension_part(
         {:<-, _meta_1, [{:when, _meta_2, [match, guard]}, enumerable]},
         acc,
         context
       ) do
    accumulate_comprehension_generator(acc, enumerable, match, guard, context)
  end

  defp transform_comprehension_part({:<-, _meta, [match, enumerable]}, acc, context) do
    accumulate_comprehension_generator(acc, enumerable, match, nil, context)
  end

  defp transform_comprehension_part(ast, acc, context) when is_list(ast) do
    Enum.reduce(ast, acc, &transform_comprehension_opt(&1, &2, context))
  end

  defp transform_comprehension_part(filter, acc, context) do
    filter = %IR.ComprehensionFilter{expression: transform(filter, context)}
    %{acc | filters: [filter | acc.filters]}
  end

  defp transform_comprehension_opt({:do, block}, acc, context) do
    %{acc | mapper: transform(block, context)}
  end

  defp transform_comprehension_opt({:into, collectable}, acc, context) do
    %{acc | collectable: transform(collectable, context)}
  end

  defp transform_comprehension_opt({:uniq, unique}, acc, context) do
    %{acc | unique: transform(unique, context)}
  end

  defp transform_function_capture(function, arity, meta, context) do
    args = build_function_capture_args(arity, meta)
    ast = {:fn, meta, [{:->, meta, [args, {:__block__, [], [{function, meta, args}]}]}]}
    transform(ast, context)
  end

  defp transform_list(list, context) do
    list
    |> List.wrap()
    |> Enum.map(&transform(&1, context))
  end
end
