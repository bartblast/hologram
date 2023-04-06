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

  def transform(ast, _context) when is_atom(ast) do
    %IR.AtomType{value: ast}
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

  def transform(ast, _context) when is_integer(ast) do
    %IR.IntegerType{value: ast}
  end

  def transform(ast, context) when is_list(ast) do
    %IR.ListType{data: transform_list(ast, context)}
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

  def transform({:^, _, [{name, _, _}]}, _context) do
    %IR.PinOperator{name: name}
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

  defp build_tuple_type_ir(data, context) do
    %IR.TupleType{data: transform_list(data, context)}
  end

  defp transform_list(list, context) do
    list
    |> List.wrap()
    |> Enum.map(&transform(&1, context))
  end
end
