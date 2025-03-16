defmodule Hologram.Compiler.Transformer do
  @moduledoc false

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
  def transform({:&, meta, [{:/, _meta_2, [{function_ast, _meta_3, nil}, arity]}]}, context) do
    function_ast
    |> transform_function_capture(arity, meta, context)
    |> Map.put(:captured_function, function_ast)
    |> Map.put(:captured_module, context.module)
  end

  # Remote Elixir function capture
  def transform(
        {:&, meta,
         [
           {:/, _meta_2,
            [
              {{:., _meta_3, [{:__aliases__, _meta_4, module_segments}, function]} = function_ast,
               _meta_5, []},
              arity
            ]}
         ]},
        context
      ) do
    function_ast
    |> transform_function_capture(arity, meta, context)
    |> Map.put(:captured_function, function)
    |> Map.put(:captured_module, Module.safe_concat(module_segments))
  end

  # Remote Erlang function capture
  def transform(
        {:&, meta,
         [
           {:/, _meta_2,
            [
              {{:., _meta_3, [module, function]} = function_ast, _meta_4, []},
              arity
            ]}
         ]},
        context
      )
      when is_atom(module) and is_atom(function) do
    function_ast
    |> transform_function_capture(arity, meta, context)
    |> Map.put(:captured_function, function)
    |> Map.put(:captured_module, module)
  end

  # Remote function capture with variable module
  def transform({:&, meta, [{:/, _meta_2, [{function_ast, _meta_3, []}, arity]}]}, context) do
    transform_function_capture(function_ast, arity, meta, context)
  end

  # Param capture
  # sobelow_skip ["DOS.BinToAtom"]
  def transform({:&, _meta, [index]}, _context) when is_integer(index) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    transform_variable(:"$#{index}", nil)
  end

  # Param capture
  # sobelow_skip ["DOS.BinToAtom"]
  def transform({:capture, meta, nil}, _context) do
    case Keyword.get(meta, :counter) do
      {_module, index} ->
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        transform_variable(:"$#{index}", nil)

      _fallback ->
        transform_variable(:capture, meta)
    end
  end

  # Anonymous function capture
  def transform({:&, meta, body}, context) do
    arity = determine_function_capture_arity(body, 0)
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
      |> filter_out_empty_bitstring_segments()

    %IR.BitstringType{segments: segments_ir}
  end

  def transform({:__block__, _meta, exprs}, context) do
    exprs_ir = Enum.map(exprs, &transform(&1, context))
    %IR.Block{expressions: exprs_ir}
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
    initial_acc = %{
      generators: [],
      filters: [],
      collectable: %IR.ListType{data: []},
      unique: %IR.AtomType{value: false},
      mapper: nil,
      reducer: nil
    }

    %{
      generators: generators,
      filters: filters,
      collectable: collectable,
      unique: unique,
      mapper: mapper,
      reducer: reducer
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
      mapper: mapper,
      reducer: reducer
    }
  end

  def transform({:for, meta, module}, _context) when not is_list(module) do
    transform_variable(:for, meta)
  end

  def transform({:cond, _meta, [[do: clauses]]}, context) do
    clauses_ir = Enum.map(clauses, &build_cond_clause_ir(&1, context))

    %IR.Cond{clauses: clauses_ir}
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
      when marker in [:def, :defp] and (is_list(params) or is_nil(params)) do
    transform_function_definition(marker, name, List.wrap(params), nil, body, context)
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

  def transform(value, _context) when is_pid(value) do
    %IR.PIDType{value: value}
  end

  def transform({:^, _meta, [variable_ast]}, context) do
    %IR.PinOperator{variable: transform(variable_ast, context)}
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

  def transform({:try, _meta, [opts]}, context) do
    initial_acc = %{
      body: nil,
      rescue_clauses: [],
      catch_clauses: [],
      else_clauses: [],
      after_block: nil
    }

    %{
      body: body,
      rescue_clauses: rescue_clauses,
      catch_clauses: catch_clauses,
      else_clauses: else_clauses,
      after_block: after_block
    } =
      Enum.reduce(
        opts,
        initial_acc,
        &transform_try_opt(&1, &2, context)
      )

    %IR.Try{
      body: body,
      rescue_clauses: rescue_clauses,
      catch_clauses: catch_clauses,
      else_clauses: else_clauses,
      after_block: after_block
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

  # TODO: finish implementing
  def transform({:with, _meta, parts}, _context) when is_list(parts) do
    %IR.With{}
  end

  # --- PRESERVE ORDER (BEGIN) ---

  def transform({{:., _meta_2, [module, function]}, _meta_1, args}, context) do
    transform_remote_function_call(module, function, args, context)
  end

  def transform({name, meta, module}, _context) when is_atom(name) and not is_list(module) do
    transform_variable(name, meta)
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

  defp build_function_capture_args(0, _meta), do: []

  # sobelow_skip ["DOS.BinToAtom"]
  defp build_function_capture_args(arity, meta) do
    arg_meta = Keyword.put(meta, :version, nil)

    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Enum.map(1..arity, &{:"$#{&1}", arg_meta, nil})
  end

  defp build_try_catch_clause(kind, value, guards, body, context) do
    kind_ir =
      if kind do
        transform(kind, context)
      else
        %IR.AtomType{value: :throw}
      end

    guards_ir =
      if guards do
        transform_guards(guards, context)
      else
        []
      end

    %IR.TryCatchClause{
      kind: kind_ir,
      value: transform(value, context),
      guards: guards_ir,
      body: transform(body, context)
    }
  end

  defp build_try_rescue_clause(variable, modules, body, context) do
    variable_ir =
      if variable do
        transform(variable, context)
      else
        nil
      end

    %IR.TryRescueClause{
      variable: variable_ir,
      modules: transform_list(modules, context),
      body: transform(body, context)
    }
  end

  defp build_tuple_type_ir(data, context) do
    %IR.TupleType{data: transform_list(data, context)}
  end

  defp determine_function_capture_arity({:&, _meta, [index]}, arity)
       when is_integer(index) and index > arity,
       do: index

  defp determine_function_capture_arity(ast, arity) when is_list(ast) do
    Enum.reduce(ast, arity, &determine_function_capture_arity/2)
  end

  defp determine_function_capture_arity({_marker, _meta, children}, arity)
       when is_list(children) do
    determine_function_capture_arity(children, arity)
  end

  defp determine_function_capture_arity(_ast, arity), do: arity

  defp filter_out_empty_bitstring_segments(segments) do
    Enum.reject(segments, &match?(%IR.BitstringSegment{value: %IR.StringType{value: ""}}, &1))
  end

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

  defp has_cons_operator?([]), do: false

  defp has_cons_operator?(list) do
    match?({:|, _meta, _args}, List.last(list))
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
         {:->, _meta_1, [[{:when, _meta_2, params_and_guards}], body]},
         context
       ) do
    {guards, params} = List.pop_at(params_and_guards, -1)

    %IR.FunctionClause{
      params: transform_list(params, %{context | pattern?: true}),
      guards: transform_guards(guards, context),
      body: transform(body, context)
    }
  end

  defp transform_anonymous_function_clause({:->, _meta, [params, body]}, context) do
    %IR.FunctionClause{
      params: transform_list(params, %{context | pattern?: true}),
      guards: [],
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

  defp transform_bitstring_modifiers({:big, _meta, _data}, _context, modifiers) do
    [{:endianness, :big} | modifiers]
  end

  defp transform_bitstring_modifiers({:binary, _meta, _data}, _context, modifiers) do
    [{:type, :binary} | modifiers]
  end

  defp transform_bitstring_modifiers({:bits, _meta, _data}, _context, modifiers) do
    [{:type, :bitstring} | modifiers]
  end

  defp transform_bitstring_modifiers({:bitstring, _meta, _data}, _context, modifiers) do
    [{:type, :bitstring} | modifiers]
  end

  defp transform_bitstring_modifiers({:bytes, _meta, _data}, _context, modifiers) do
    [{:type, :binary} | modifiers]
  end

  defp transform_bitstring_modifiers({:float, _meta, _data}, _context, modifiers) do
    [{:type, :float} | modifiers]
  end

  defp transform_bitstring_modifiers({:integer, _meta, _data}, _context, modifiers) do
    [{:type, :integer} | modifiers]
  end

  defp transform_bitstring_modifiers({:little, _meta, _data}, _context, modifiers) do
    [{:endianness, :little} | modifiers]
  end

  defp transform_bitstring_modifiers({:native, _meta, _data}, _context, modifiers) do
    [{:endianness, :native} | modifiers]
  end

  defp transform_bitstring_modifiers({:signed, _meta, _data}, _context, modifiers) do
    [{:signedness, :signed} | modifiers]
  end

  defp transform_bitstring_modifiers({:size, _meta, [size]}, context, modifiers) do
    [{:size, transform(size, context)} | modifiers]
  end

  defp transform_bitstring_modifiers({:unit, _meta, [unit]}, _context, modifiers) do
    [{:unit, unit} | modifiers]
  end

  defp transform_bitstring_modifiers({:unsigned, _meta, _data}, _context, modifiers) do
    [{:signedness, :unsigned} | modifiers]
  end

  defp transform_bitstring_modifiers({:utf8, _meta, _data}, _context, modifiers) do
    [{:type, :utf8} | modifiers]
  end

  defp transform_bitstring_modifiers({:utf16, _meta, _data}, _context, modifiers) do
    [{:type, :utf16} | modifiers]
  end

  defp transform_bitstring_modifiers({:utf32, _meta, _data}, _context, modifiers) do
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

  defp transform_comprehension_part({:<-, _meta, _args} = ast, acc, context) do
    clause = transform(ast, context)
    %{acc | generators: [clause | acc.generators]}
  end

  defp transform_comprehension_part(opts, acc, context) when is_list(opts) do
    Enum.reduce(opts, acc, &transform_comprehension_opt(&1, &2, context))
  end

  defp transform_comprehension_part(filter, acc, context) do
    filter = %IR.ComprehensionFilter{expression: transform(filter, context)}
    %{acc | filters: [filter | acc.filters]}
  end

  defp transform_comprehension_opt(
         {:do, {:__block__, [], [[{:->, _meta, _body} | _clauses_tail] = clauses]}},
         acc,
         context
       ) do
    reducer = %{acc.reducer | clauses: transform_list(clauses, context)}
    %{acc | reducer: reducer}
  end

  defp transform_comprehension_opt({:do, block}, acc, context) do
    %{acc | mapper: transform(block, context)}
  end

  defp transform_comprehension_opt({:into, collectable}, acc, context) do
    %{acc | collectable: transform(collectable, context)}
  end

  defp transform_comprehension_opt({:reduce, initial_value}, acc, context) do
    reducer = %{
      initial_value: transform(initial_value, context),
      clauses: []
    }

    %{acc | reducer: reducer}
  end

  defp transform_comprehension_opt({:uniq, unique}, acc, context) do
    %{acc | unique: transform(unique, context)}
  end

  defp transform_function_capture(function_ast, arity, meta, context) do
    args = build_function_capture_args(arity, meta)
    ast = {:fn, meta, [{:->, meta, [args, {:__block__, [], [{function_ast, meta, args}]}]}]}
    transform(ast, context)
  end

  defp transform_function_definition(marker, name, params, guards, body, context) do
    visibility =
      if marker == :def do
        :public
      else
        :private
      end

    guards_ir =
      if guards do
        transform_guards(guards, context)
      else
        []
      end

    params_ir = transform_list(params, %{context | pattern?: true})

    %IR.FunctionDefinition{
      name: name,
      arity: Enum.count(params_ir),
      visibility: visibility,
      clause: %IR.FunctionClause{
        params: params_ir,
        guards: guards_ir,
        body: transform(body, context)
      }
    }
  end

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
    catch_clauses = Enum.map(clauses, &transform_try_catch_clause(&1, context))
    %{acc | catch_clauses: catch_clauses}
  end

  defp transform_try_opt({:do, block}, acc, context) do
    %{acc | body: transform(block, context)}
  end

  defp transform_try_opt({:else, clauses}, acc, context) do
    %{acc | else_clauses: transform_list(clauses, context)}
  end

  defp transform_try_opt({:rescue, clauses}, acc, context) do
    rescue_clauses = Enum.map(clauses, &transform_try_rescue_clause(&1, context))
    %{acc | rescue_clauses: rescue_clauses}
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

  defp transform_variable(name, meta) when is_list(meta) do
    version = Keyword.get(meta, :version)
    transform_variable(name, version)
  end

  defp transform_variable(name, version) do
    case to_string(name) do
      "_" <> _rest ->
        %IR.MatchPlaceholder{}

      _fallback ->
        %IR.Variable{name: name, version: version}
    end
  end
end
