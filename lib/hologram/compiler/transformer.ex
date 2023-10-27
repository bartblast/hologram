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

  alias Hologram.Commons.StringUtils
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
    clauses
    |> Enum.map(&transform_anonymous_function_clause(&1, context))
    |> then(fn clauses_ir ->
      clauses_ir
      |> hd()
      |> Map.fetch!(:params)
      |> Enum.count()
      |> then(&%IR.AnonymousFunctionType{arity: &1, clauses: clauses_ir})
    end)
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
    index
    |> to_string()
    |> StringUtils.wrap("holo_arg_", "__")
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    |> String.to_atom()
    |> then(&transform({&1, meta, nil}, context))
  end

  # Partially applied anonymous function
  def transform({:&, meta, body}, context) do
    body
    |> determine_partially_applied_function_arity(0)
    |> build_function_capture_args(meta)
    |> then(&transform({:fn, meta, [{:->, meta, [&1, {:__block__, [], body}]}]}, context))
  end

  def transform(value, _context) when is_atom(value) do
    %IR.AtomType{value: value}
  end

  def transform({:<<>>, _meta, segments}, context) do
    segments
    |> Enum.map(&transform_bitstring_segment(&1, context))
    |> Enum.flat_map(fn
      %IR.BitstringSegment{value: %IR.BitstringType{segments: nested_segments}} ->
        nested_segments

      segment ->
        [segment]
    end)
    |> then(&%IR.BitstringType{segments: &1})
  end

  def transform({:__block__, _meta, exprs}, context) do
    exprs
    |> Enum.map(&transform(&1, context))
    |> then(&%IR.Block{expressions: &1})
  end

  def transform({:case, _meta, [condition, [do: clauses]]}, context) do
    %IR.Case{
      condition: transform(condition, context),
      clauses: transform_list(clauses, context)
    }
  end

  def transform({:->, _meta_1, [[{:when, _meta_2, [match, guards]}], body]}, context) do
    %IR.Clause{
      match: transform(match, context),
      guards: transform_guards(guards, context),
      body: transform(body, context)
    }
  end

  def transform({:->, _meta, [[match], body]}, context) do
    %IR.Clause{
      match: transform(match, context),
      guards: [],
      body: transform(body, context)
    }
  end

  def transform({:<-, _meta_1, [{:when, _meta_2, [match, guards]}, body]}, context) do
    %IR.Clause{
      match: transform(match, context),
      guards: transform_guards(guards, context),
      body: transform(body, context)
    }
  end

  def transform({:<-, _meta, [match, body]}, context) do
    %IR.Clause{
      match: transform(match, context),
      guards: [],
      body: transform(body, context)
    }
  end

  def transform({:for, _meta, parts}, context) when is_list(parts) do
    %IR.Comprehension{
      generators: [],
      filters: [],
      collectable: %IR.ListType{data: []},
      unique: %IR.AtomType{value: false},
      mapper: nil,
      reducer: nil
    }
    |> then(fn ir_comprehension ->
      Enum.reduce(parts, ir_comprehension, &transform_comprehension_part(&1, &2, context))
    end)
    |> then(&%{&1 | filters: Enum.reverse(&1.filters)})
    |> then(&%{&1 | generators: Enum.reverse(&1.generators)})
  end

  def transform({:for, _meta, module}, _context) when not is_list(module) do
    transform_variable(:for)
  end

  def transform({:cond, _meta, [[do: clauses]]}, context) do
    clauses
    |> Enum.map(&build_cond_clause_ir(&1, context))
    |> then(&%IR.Cond{clauses: &1})
  end

  def transform([{:|, _meta, [head, tail]}], context) do
    %IR.ConsOperator{
      head: transform(head, context),
      tail: transform(tail, context)
    }
  end

  def transform({{:., _meta_2, [{marker, _meta_3, _module} = left, right]}, meta, []}, context)
      when marker != :__aliases__ do
    if {:no_parens, true} in meta do
      %IR.DotOperator{
        left: transform(left, context),
        right: transform(right, context)
      }
    else
      transform_remote_function_call(left, right, [], context)
    end
  end

  def transform(value, _context) when is_float(value) do
    %IR.FloatType{value: value}
  end

  def transform(
        {marker, _meta_1, [{:when, _meta_2, [{name, _meta_3, params}, guards]}, [do: body]]},
        context
      )
      when marker in [:def, :defp] do
    transform_function_definition(marker, name, params, guards, body, context)
  end

  def transform({marker, _meta_1, [{name, _meta_2, params}, [do: body]]}, context)
      when marker in [:def, :defp] and is_list(params) do
    transform_function_definition(marker, name, params, nil, body, context)
  end

  def transform({marker, _meta_1, [{name, _meta_2, module}, [do: body]]}, context)
      when marker in [:def, :defp] and is_atom(module) do
    transform_function_definition(marker, name, [], nil, body, context)
  end

  def transform(value, _context) when is_integer(value) do
    %IR.IntegerType{value: value}
  end

  def transform(list, context) when is_list(list) do
    if has_cons_operator?(list) do
      transform_list_with_cons_operator(list, context)
    else
      %IR.ListType{data: transform_list(list, context)}
    end
  end

  def transform({:defmacro, _meta, _args}, _context) do
    %IR.IgnoredExpression{type: :public_macro_definition}
  end

  def transform({:defmacrop, _meta, _args}, _context) do
    %IR.IgnoredExpression{type: :private_macro_definition}
  end

  # Map with cons operator is transformed to Map.merge/2 remote function call.
  def transform({:%{}, _meta_1, [{:|, _meta_2, [map_1, data_2]}]}, context) do
    %IR.RemoteFunctionCall{
      module: %IR.AtomType{value: Map},
      function: :merge,
      args: [
        transform(map_1, context),
        transform({:%{}, [], data_2}, context)
      ]
    }
  end

  def transform({:%{}, _meta, data}, context) do
    data
    |> Enum.map(fn {key, value} ->
      {transform(key, context), transform(value, context)}
    end)
    |> then(&%IR.MapType{data: &1})
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

  def transform(value, _context) when is_pid(value) do
    %IR.PIDType{value: value}
  end

  def transform({:^, _meta_1, [{name, _meta_2, _args}]}, _context) do
    %IR.PinOperator{name: name}
  end

  def transform(value, _context) when is_port(value) do
    %IR.PortType{value: value}
  end

  def transform(value, _context) when is_reference(value) do
    %IR.ReferenceType{value: value}
  end

  def transform(value, _context) when is_binary(value) do
    %IR.StringType{value: value}
  end

  # Struct with cons operator is transformed to nested Map.merge/2 and __struct__/1 remote function calls.
  def transform({:%, _meta_1, [module, {:%{}, _meta_2, [{:|, _meta_3, [map, data]}]}]}, context) do
    then(
      %IR.RemoteFunctionCall{
        module: transform(module, context),
        function: :__struct__,
        args: [transform(data, context)]
      },
      &%IR.RemoteFunctionCall{
        module: %IR.AtomType{value: Map},
        function: :merge,
        args: [transform(map, context), &1]
      }
    )
  end

  # Struct without cons operator inside a pattern is transformed into map IR in place.
  def transform({:%, _meta, [module, {:%{}, meta, data}]}, %Context{pattern?: true} = context) do
    then([{:__struct__, module} | data], &transform({:%{}, meta, &1}, context))
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

  def transform({:try, _meta, [opts]}, context) do
    Enum.reduce(
      opts,
      %IR.Try{catch_clauses: [], else_clauses: [], rescue_clauses: []},
      &transform_try_opt(&1, &2, context)
    )
  end

  def transform({:{}, _meta, data}, context) do
    build_tuple_type_ir(data, context)
  end

  def transform({_el_1, _el_2} = data, context) do
    data
    |> Tuple.to_list()
    |> build_tuple_type_ir(context)
  end

  # TODO: finish implementing
  def transform({:with, _meta, parts}, _context) when is_list(parts) do
    %IR.With{}
  end

  # --- PRESERVE ORDER (BEGIN) ---

  def transform({{:., _meta_2, [module, function]}, _meta_1, args}, context) do
    transform_remote_function_call(module, function, args, context)
  end

  def transform({name, _meta, module}, _context) when is_atom(name) and not is_list(module) do
    transform_variable(name)
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

  defp build_try_catch_clause(kind, value, guards, body, context) do
    %IR.TryCatchClause{
      body: transform(body, context),
      guards: transform_guards(guards, context),
      kind: kind && transform(kind, context),
      value: transform(value, context)
    }
  end

  defp build_try_rescue_clause(variable, modules, body, context) do
    %IR.TryRescueClause{
      variable: variable && transform(variable, context),
      modules: transform_list(modules, context),
      body: transform(body, context)
    }
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

  defp has_cons_operator?([]), do: false

  defp has_cons_operator?(list) do
    match?({:|, _meta, _args}, List.last(list))
  end

  # N/A - nested bitstring and generators
  defp maybe_add_default_bitstring_type_modifier(%type{}, modifiers)
       when type in [IR.BitstringType, IR.Clause] do
    modifiers
  end

  # defaults to integer
  defp maybe_add_default_bitstring_type_modifier(%type{}, modifiers)
       when type in [IR.RemoteFunctionCall, IR.Variable] do
    maybe_add_default_bitstring_type_modifier(%IR.IntegerType{}, modifiers)
  end

  defp maybe_add_default_bitstring_type_modifier(%IR.FloatType{}, modifiers) do
    [{:type, :float} | modifiers]
  end

  defp maybe_add_default_bitstring_type_modifier(%IR.IntegerType{}, modifiers) do
    [{:type, :integer} | modifiers]
  end

  defp maybe_add_default_bitstring_type_modifier(%IR.StringType{}, modifiers) do
    [{:type, :utf8} | modifiers]
  end

  defp transform_anonymous_function_clause(
         {:->, _meta_1, [[{:when, _meta_2, params_and_guards}], body]},
         context
       ) do
    params_and_guards
    |> List.pop_at(-1)
    |> then(fn {guards, params} ->
      %IR.FunctionClause{
        params: transform_list(params, %{context | pattern?: true}),
        guards: transform_guards(guards, context),
        body: transform(body, context)
      }
    end)
  end

  defp transform_anonymous_function_clause({:->, _meta, [params, body]}, context) do
    %IR.FunctionClause{
      params: transform_list(params, %{context | pattern?: true}),
      guards: [],
      body: transform(body, context)
    }
  end

  defp transform_bitstring_modifiers({:-, _meta, [left, right]}, context, modifiers) do
    left
    |> transform_bitstring_modifiers(context, modifiers)
    |> then(&transform_bitstring_modifiers(right, context, &1))
  end

  defp transform_bitstring_modifiers({:*, _meta, [size, unit]}, context, modifiers) do
    size
    |> transform(context)
    |> then(&[{:unit, unit} | [{:size, &1} | modifiers]])
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
    size
    |> transform(context)
    |> then(&[{:size, &1} | modifiers])
  end

  defp transform_bitstring_segment({:"::", _meta, [left, right]}, context) do
    right
    |> transform_bitstring_modifiers(context, [])
    |> then(&transform_bitstring_segment(left, &1, context))
  end

  defp transform_bitstring_segment(ast, context) do
    transform_bitstring_segment(ast, [], context)
  end

  defp transform_bitstring_segment(left, right, context) do
    left
    |> transform(context)
    |> then(fn value ->
      right
      |> Keyword.has_key?(:type)
      |> then(fn
        true -> right
        false -> maybe_add_default_bitstring_type_modifier(value, right)
      end)
      |> then(&%IR.BitstringSegment{modifiers: &1, value: value})
    end)
  end

  defp transform_comprehension_part({:<-, _meta, _args} = ast, acc, context) do
    ast
    |> transform(context)
    |> then(&%{acc | generators: [&1 | acc.generators]})
  end

  defp transform_comprehension_part(opts, acc, context) when is_list(opts) do
    Enum.reduce(opts, acc, &transform_comprehension_opt(&1, &2, context))
  end

  defp transform_comprehension_part(filter, acc, context) do
    filter
    |> transform(context)
    |> then(&%{acc | filters: [%IR.ComprehensionFilter{expression: &1} | acc.filters]})
  end

  defp transform_comprehension_opt(
         {:do, {:__block__, [], [[{:->, _meta, _body} | _clauses_tail] = clauses]}},
         acc,
         context
       ) do
    clauses
    |> transform_list(context)
    |> then(&%{acc | reducer: %{acc.reducer | clauses: &1}})
  end

  defp transform_comprehension_opt({:do, block}, acc, context) do
    %{acc | mapper: transform(block, context)}
  end

  defp transform_comprehension_opt({:into, collectable}, acc, context) do
    %{acc | collectable: transform(collectable, context)}
  end

  defp transform_comprehension_opt({:reduce, initial_value}, acc, context) do
    initial_value
    |> transform(context)
    |> then(&%{acc | reducer: %{clauses: [], initial_value: &1}})
  end

  defp transform_comprehension_opt({:uniq, unique}, acc, context) do
    %{acc | unique: transform(unique, context)}
  end

  defp transform_function_capture(function, arity, meta, context) do
    arity
    |> build_function_capture_args(meta)
    |> then(&[&1, {:__block__, [], [{function, meta, &1}]}])
    |> then(&{:fn, meta, [{:->, meta, &1}]})
    |> then(&transform(&1, context))
  end

  defp transform_function_definition(marker, name, params, guards, body, context) do
    marker
    |> then(fn
      :def -> :public
      _marker -> :private
    end)
    |> then(&{&1, transform_guards(guards, context)})
    |> then(fn {visibility, guards_ir} ->
      params
      |> transform_list(%{context | pattern?: true})
      |> then(fn params_ir ->
        body
        |> transform(context)
        |> then(&%IR.FunctionClause{params: params_ir, guards: guards_ir, body: &1})
        |> then(
          &%IR.FunctionDefinition{
            name: name,
            arity: Enum.count(params_ir),
            visibility: visibility,
            clause: &1
          }
        )
      end)
    end)
  end

  defp transform_guards(nil, _context), do: []

  defp transform_guards({:when, _meta, [guard, rest]}, context) do
    [transform(guard, context) | transform_guards(rest, context)]
  end

  defp transform_guards(ast, context) do
    [transform(ast, context)]
  end

  defp transform_list(list, context) do
    list
    |> List.wrap()
    |> Enum.map(&transform(&1, context))
  end

  defp transform_list_with_cons_operator(list, context) do
    list
    |> Enum.reverse()
    |> Enum.reduce(nil, fn
      {:|, _meta, [head, tail]}, nil ->
        %IR.ConsOperator{
          head: transform(head, context),
          tail: transform(tail, context)
        }

      item, acc ->
        %IR.ConsOperator{
          head: transform(item, context),
          tail: acc
        }
    end)
  end

  defp transform_remote_function_call(module, function, args, context) do
    %IR.RemoteFunctionCall{
      module: transform(module, context),
      function: function,
      args: transform_list(args, context)
    }
  end

  defp transform_try_catch_clause(
         {:->, _meta_1, [[{:when, _meta_2, [kind, value, guards]}], body]},
         context
       ) do
    build_try_catch_clause(kind, value, guards, body, context)
  end

  defp transform_try_catch_clause(
         {:->, _meta_1, [[{:when, _meta_2, [value, guards]}], body]},
         context
       ) do
    build_try_catch_clause(nil, value, guards, body, context)
  end

  defp transform_try_catch_clause({:->, _meta, [[kind, value], body]}, context) do
    build_try_catch_clause(kind, value, nil, body, context)
  end

  defp transform_try_catch_clause({:->, _meta, [[value], body]}, context) do
    build_try_catch_clause(nil, value, nil, body, context)
  end

  defp transform_try_opt({:after, block}, acc, context) do
    %{acc | after_block: transform(block, context)}
  end

  defp transform_try_opt({:catch, clauses}, acc, context) do
    clauses
    |> Enum.map(&transform_try_catch_clause(&1, context))
    |> then(&%{acc | catch_clauses: &1})
  end

  defp transform_try_opt({:do, block}, acc, context) do
    %{acc | body: transform(block, context)}
  end

  defp transform_try_opt({:else, clauses}, acc, context) do
    %{acc | else_clauses: transform_list(clauses, context)}
  end

  defp transform_try_opt({:rescue, clauses}, acc, context) do
    clauses
    |> Enum.map(&transform_try_rescue_clause(&1, context))
    |> then(&%{acc | rescue_clauses: &1})
  end

  defp transform_try_rescue_clause(
         {:->, _meta_1, [[{:in, _meta_2, [variable, modules]}], body]},
         context
       ) do
    build_try_rescue_clause(variable, modules, body, context)
  end

  defp transform_try_rescue_clause(
         {:->, _meta_1, [[{:__aliases__, _meta_2, _segments} = module], body]},
         context
       ) do
    build_try_rescue_clause(nil, [module], body, context)
  end

  defp transform_try_rescue_clause({:->, _meta_1, [[modules], body]}, context)
       when is_list(modules) do
    build_try_rescue_clause(nil, modules, body, context)
  end

  defp transform_try_rescue_clause({:->, _meta_1, [[variable], body]}, context) do
    build_try_rescue_clause(variable, [], body, context)
  end

  defp transform_variable(name) do
    name
    |> to_string()
    |> then(fn
      "_" <> _rest -> %IR.MatchPlaceholder{}
      _fallback -> %IR.Variable{name: name}
    end)
  end
end
