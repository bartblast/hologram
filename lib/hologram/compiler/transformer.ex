defmodule Hologram.Compiler.Transformer do
  if Application.compile_env(:hologram, :debug_transformer) do
    use Interceptor.Annotated,
      config: %{
        {Hologram.Compiler.Transformer, :transform, 1} => [
          after: {Hologram.Compiler.Transformer, :debug, 2}
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

  def transform({{:., _, [function]}, _, args}, context) do
    %IR.AnonymousFunctionCall{
      function: transform(function, context),
      args: transform_list(args, context)
    }
  end

  def transform({:fn, _, clauses}, context) do
    clauses_ir =
      Enum.map(clauses, fn {:->, _, [params, body]} ->
        %IR.AnonymousFunctionClause{
          params: transform_list(params, context),
          body: transform(body, context)
        }
      end)

    arity =
      clauses_ir
      |> hd()
      |> Map.get(:params)
      |> Enum.count()

    %IR.AnonymousFunctionType{
      arity: arity,
      clauses: clauses_ir
    }
  end

  def transform(ast, _context) when is_atom(ast) do
    %IR.AtomType{value: ast}
  end

  def transform({:<<>>, _, segments}, context) do
    segments_ir =
      segments
      |> Enum.map(&transform_bitstring_segment(&1, context, %IR.BitstringSegment{}))
      |> flatten_bitstring_segments()

    %IR.BitstringType{segments: segments_ir}
  end

  def transform({:__block__, _, ast}, context) do
    exprs = Enum.map(ast, &transform(&1, context))
    %IR.Block{expressions: exprs}
  end

  def transform({:case, _, [condition, [do: clauses]]}, context) do
    condition_ir = transform(condition, context)
    clauses_ir = Enum.map(clauses, &build_case_expression_clause_ir(&1, context))

    %IR.CaseExpression{
      condition: condition_ir,
      clauses: clauses_ir
    }
  end

  def transform([{:|, _, [head, tail]}], context) do
    %IR.ConsOperator{
      head: transform(head, context),
      tail: transform(tail, context)
    }
  end

  def transform({{:., _, [{marker, _, _} = left, right]}, [{:no_parens, true} | _], []}, context)
      when marker != :__aliases__ do
    %IR.DotOperator{
      left: transform(left, context),
      right: transform(right, context)
    }
  end

  def transform(ast, _context) when is_float(ast) do
    %IR.FloatType{value: ast}
  end

  def transform({marker, _, [{name, _, params}, [do: body]]}, context)
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

  def transform(ast, _context) when is_integer(ast) do
    %IR.IntegerType{value: ast}
  end

  def transform(ast, context) when is_list(ast) do
    %IR.ListType{data: transform_list(ast, context)}
  end

  def transform({:defmacro, _, _}, _context) do
    %IR.IgnoredExpression{type: :public_macro_definition}
  end

  def transform({:defmacrop, _, _}, _context) do
    %IR.IgnoredExpression{type: :private_macro_definition}
  end

  # Map with cons operator is transformed to Map.merge/2 remote function call.
  def transform({:%{}, _, [{:|, _, [map, data]}]}, context) do
    %IR.RemoteFunctionCall{
      module: %IR.AtomType{value: Map},
      function: :merge,
      args: [
        transform(map, context),
        %IR.MapType{data: transform_list(data, context)}
      ]
    }
  end

  def transform({:%{}, _, data}, context) do
    data_ir =
      Enum.map(data, fn {key, value} ->
        {transform(key, context), transform(value, context)}
      end)

    %IR.MapType{data: data_ir}
  end

  def transform({:=, _, [left, right]}, context) do
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
  def transform({:__aliases__, _, alias_segs}, context) do
    alias_segs
    |> Helpers.module()
    |> transform(context)
  end

  # Module attributes are expanded by beam_file package, but we still need them for templates.
  def transform({:@, _, [{name, _, ast}]}, _context) when not is_list(ast) do
    %IR.ModuleAttributeOperator{name: name}
  end

  def transform({:defmodule, _, [module, [do: body]]}, context) do
    %IR.ModuleDefinition{
      module: transform(module, context),
      body: transform(body, context)
    }
  end

  def transform({:^, _, [{name, _, _}]}, _context) do
    %IR.PinOperator{name: name}
  end

  def transform(value, _context) when is_binary(value) do
    %IR.StringType{value: value}
  end

  # Struct with cons operator is transformed to nested Map.merge/2 and __struct__/1 remote function calls.
  def transform({:%, _, [module, {:%{}, _, [{:|, _, [map, data]}]}]}, context) do
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
  def transform({:%, _, [module, {:%{}, meta, data}]}, %Context{pattern?: true} = context) do
    new_data = [{:__struct__, module} | data]
    transform({:%{}, meta, new_data}, context)
  end

  # Struct without cons operator not in a pattern is transformed to __struct__/1 remote function call.
  def transform({:%, _, [module, {:%{}, _, data}]}, %Context{pattern?: false} = context) do
    %IR.RemoteFunctionCall{
      module: transform(module, context),
      function: :__struct__,
      args: [transform(data, context)]
    }
  end

  def transform({:{}, _, data}, context) do
    build_tuple_type_ir(data, context)
  end

  def transform({_, _} = data, context) do
    data
    |> Tuple.to_list()
    |> build_tuple_type_ir(context)
  end

  # --- PRESERVE ORDER (BEGIN) ---

  def transform({{:., _, [module, function]}, _, args}, context) do
    %IR.RemoteFunctionCall{
      module: transform(module, context),
      function: function,
      args: transform_list(args, context)
    }
  end

  def transform({name, _, nil}, _context) when is_atom(name) do
    case to_string(name) do
      "_" <> _ ->
        %IR.MatchPlaceholder{}

      _ ->
        %IR.Variable{name: name}
    end
  end

  def transform({function, _, args}, context) when is_atom(function) and is_list(args) do
    %IR.LocalFunctionCall{
      function: function,
      args: transform_list(args, context)
    }
  end

  # --- PRESERVE ORDER (END) ---

  @doc """
  Prints debug info for intercepted transform/1 call.
  """
  @spec debug({module, atom, [AST.t()]}, IR.t()) :: :ok
  def debug({_module, _function, [ast] = _args}, result) do
    IO.puts("\nTRANSFORM...............................\n")
    IO.puts("ast")
    # credo:disable-for-next-line Credo.Check.Warning.IoInspect
    IO.inspect(ast)
    IO.puts("")
    IO.puts("result")
    # credo:disable-for-next-line Credo.Check.Warning.IoInspect
    IO.inspect(result)
    IO.puts("\n........................................\n")
  end

  defp build_case_expression_clause_ir({:->, _, [[head], body]}, context) do
    %IR.CaseExpressionClause{
      head: transform(head, context),
      body: transform(body, context)
    }
  end

  defp build_tuple_type_ir(data, context) do
    %IR.TupleType{data: transform_list(data, context)}
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

  defp maybe_add_default_bitstring_modifiers(segment) do
    segment
    |> maybe_add_default_bitstring_type_modifier()
    |> maybe_add_default_bitstring_endianness_modifier()
    |> maybe_add_default_bitstring_signedness_modifier()
    |> maybe_add_default_bitstring_size_modifier()
    |> maybe_add_default_bitstring_unit_modifier()
  end

  defp maybe_add_default_bitstring_endianness_modifier(%{endianness: nil} = segment) do
    %{segment | endianness: :big}
  end

  defp maybe_add_default_bitstring_endianness_modifier(segment), do: segment

  defp maybe_add_default_bitstring_signedness_modifier(%{signedness: nil, type: type} = segment)
       when type in [:float, :integer] do
    %{segment | signedness: :unsigned}
  end

  # Signed and unsigned modifiers are supported only for integer and float types
  defp maybe_add_default_bitstring_signedness_modifier(%{signedness: nil} = segment) do
    %{segment | signedness: :not_applicable}
  end

  defp maybe_add_default_bitstring_signedness_modifier(segment), do: segment

  defp maybe_add_default_bitstring_size_modifier(%{size: nil, type: :float} = segment) do
    %{segment | size: %IR.IntegerType{value: 64}}
  end

  defp maybe_add_default_bitstring_size_modifier(%{size: nil, type: :integer} = segment) do
    %{segment | size: %IR.IntegerType{value: 8}}
  end

  defp maybe_add_default_bitstring_size_modifier(
         %{size: nil, value: %IR.StringType{value: value}} = segment
       ) do
    %{segment | size: %IR.IntegerType{value: String.length(value)}}
  end

  defp maybe_add_default_bitstring_size_modifier(%{size: nil} = segment) do
    %{segment | size: %IR.AtomType{value: nil}}
  end

  defp maybe_add_default_bitstring_size_modifier(segment), do: segment

  defp maybe_add_default_bitstring_type_modifier(%{type: nil, value: %IR.FloatType{}} = segment) do
    %{segment | type: :float}
  end

  defp maybe_add_default_bitstring_type_modifier(%{type: nil, value: %IR.StringType{}} = segment) do
    %{segment | type: :utf8}
  end

  defp maybe_add_default_bitstring_type_modifier(%{type: nil} = segment) do
    %{segment | type: :integer}
  end

  defp maybe_add_default_bitstring_type_modifier(segment), do: segment

  defp maybe_add_default_bitstring_unit_modifier(%{type: :binary, unit: nil} = segment) do
    %{segment | unit: 8}
  end

  defp maybe_add_default_bitstring_unit_modifier(%{type: :float, unit: nil} = segment) do
    %{segment | unit: 1}
  end

  defp maybe_add_default_bitstring_unit_modifier(%{type: :integer, unit: nil} = segment) do
    %{segment | unit: 1}
  end

  defp maybe_add_default_bitstring_unit_modifier(%{type: :utf8, unit: nil} = segment) do
    %{segment | unit: 8}
  end

  defp maybe_add_default_bitstring_unit_modifier(%{type: :utf16, unit: nil} = segment) do
    %{segment | unit: 16}
  end

  defp maybe_add_default_bitstring_unit_modifier(%{type: :utf32, unit: nil} = segment) do
    %{segment | unit: 32}
  end

  defp maybe_add_default_bitstring_unit_modifier(segment), do: segment

  defp transform_bitstring_modifiers({:-, _, [left, right]}, context, acc) do
    new_acc = transform_bitstring_modifiers(left, context, acc)
    transform_bitstring_modifiers(right, context, new_acc)
  end

  defp transform_bitstring_modifiers({:*, _, [size, unit]}, context, acc) do
    %{acc | size: transform(size, context), unit: unit}
  end

  defp transform_bitstring_modifiers({:big, _, _}, _context, acc) do
    %{acc | endianness: :big}
  end

  defp transform_bitstring_modifiers({:binary, _, _}, _context, acc) do
    %{acc | type: :binary}
  end

  defp transform_bitstring_modifiers({:bits, _, _}, _context, acc) do
    %{acc | type: :bitstring}
  end

  defp transform_bitstring_modifiers({:bitstring, _, _}, _context, acc) do
    %{acc | type: :bitstring}
  end

  defp transform_bitstring_modifiers({:bytes, _, _}, _context, acc) do
    %{acc | type: :binary}
  end

  defp transform_bitstring_modifiers({:float, _, _}, _context, acc) do
    %{acc | type: :float}
  end

  defp transform_bitstring_modifiers({:integer, _, _}, _context, acc) do
    %{acc | type: :integer}
  end

  defp transform_bitstring_modifiers({:little, _, _}, _context, acc) do
    %{acc | endianness: :little}
  end

  defp transform_bitstring_modifiers({:native, _, _}, _context, acc) do
    %{acc | endianness: :native}
  end

  defp transform_bitstring_modifiers({:signed, _, _}, _context, acc) do
    %{acc | signedness: :signed}
  end

  defp transform_bitstring_modifiers({:size, _, [size]}, context, acc) do
    %{acc | size: transform(size, context)}
  end

  defp transform_bitstring_modifiers({:unit, _, [unit]}, _context, acc) do
    %{acc | unit: unit}
  end

  defp transform_bitstring_modifiers({:unsigned, _, _}, _context, acc) do
    %{acc | signedness: :unsigned}
  end

  defp transform_bitstring_modifiers({:utf8, _, _}, _context, acc) do
    %{acc | type: :utf8}
  end

  defp transform_bitstring_modifiers({:utf16, _, _}, _context, acc) do
    %{acc | type: :utf16}
  end

  defp transform_bitstring_modifiers({:utf32, _, _}, _context, acc) do
    %{acc | type: :utf32}
  end

  defp transform_bitstring_modifiers(size, context, acc) do
    %{acc | size: transform(size, context)}
  end

  defp transform_bitstring_segment({:"::", _, [left, right]}, context, acc) do
    new_acc = %{acc | value: transform(left, context)}

    transform_bitstring_modifiers(right, context, new_acc)
    |> maybe_add_default_bitstring_modifiers()
  end

  defp transform_bitstring_segment(ast, context, acc) do
    %{acc | value: transform(ast, context)}
    |> maybe_add_default_bitstring_modifiers()
  end

  defp transform_list(list, context) do
    list
    |> List.wrap()
    |> Enum.map(&transform(&1, context))
  end
end
