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
  @spec transform(AST.t()) :: IR.t()
  def transform(ast)

  def transform({{:., _, [function]}, _, args}) do
    %IR.AnonymousFunctionCall{
      function: transform(function),
      args: transform_list(args)
    }
  end

  def transform(ast) when is_atom(ast) do
    %IR.AtomType{value: ast}
  end

  def transform([{:|, _, [head, tail]}]) do
    %IR.ConsOperator{
      head: transform(head),
      tail: transform(tail)
    }
  end

  def transform({{:., _, [{marker, _, _} = left, right]}, [{:no_parens, true} | _], []})
      when marker != :__aliases__ do
    %IR.DotOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform(ast) when is_float(ast) do
    %IR.FloatType{value: ast}
  end

  def transform(ast) when is_integer(ast) do
    %IR.IntegerType{value: ast}
  end

  def transform(ast) when is_list(ast) do
    %IR.ListType{data: transform_list(ast)}
  end

  def transform({:%{}, _, data}) do
    data_ir =
      Enum.map(data, fn {key, value} ->
        {transform(key), transform(value)}
      end)

    %IR.MapType{data: data_ir}
  end

  def transform({:=, _, [left, right]}) do
    %IR.MatchOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  # Modules are transformed to atom types.
  def transform({:__aliases__, meta, [:"Elixir" | alias_segs]}) do
    transform({:__aliases__, meta, alias_segs})
  end

  # Modules are transformed to atom types.
  def transform({:__aliases__, _, alias_segs}) do
    alias_segs
    |> Helpers.module()
    |> transform()
  end

  # Module attributes are expanded by beam_file package, but we still need them for templates.
  def transform({:@, _, [{name, _, ast}]}) when not is_list(ast) do
    %IR.ModuleAttributeOperator{name: name}
  end

  def transform({:^, _, [{name, _, _}]}) do
    %IR.PinOperator{name: name}
  end

  def transform({:{}, _, data}) do
    build_tuple_type_ir(data)
  end

  def transform({_, _} = data) do
    data
    |> Tuple.to_list()
    |> build_tuple_type_ir()
  end

  # --- PRESERVE ORDER (BEGIN) ---

  def transform({{:., _, [module, function]}, _, args}) do
    %IR.RemoteFunctionCall{
      module: transform(module),
      function: function,
      args: transform_list(args)
    }
  end

  def transform({name, _, nil}) when is_atom(name) do
    %IR.Variable{name: name}
  end

  def transform({function, _, args}) when is_atom(function) and is_list(args) do
    %IR.LocalFunctionCall{
      function: function,
      args: transform_list(args)
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
    # credo:disable-for-next-line
    IO.inspect(ast)
    IO.puts("")
    IO.puts("result")
    # credo:disable-for-next-line
    IO.inspect(result)
    IO.puts("\n........................................\n")
  end

  defp build_tuple_type_ir(data) do
    %IR.TupleType{data: transform_list(data)}
  end

  defp transform_list(list) do
    list
    |> List.wrap()
    |> Enum.map(&transform/1)
  end
end
