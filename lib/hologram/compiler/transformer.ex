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

  def transform(ast) when is_float(ast) do
    %IR.FloatType{value: ast}
  end

  def transform(ast) when is_integer(ast) do
    %IR.IntegerType{value: ast}
  end

  def transform(ast) when is_list(ast) do
    %IR.ListType{data: transform_list(ast)}
  end

  def transform({:__aliases__, meta, [:"Elixir" | alias_segs]}) do
    transform({:__aliases__, meta, alias_segs})
  end

  def transform({:__aliases__, _, alias_segs}) do
    module = Helpers.module(alias_segs)
    %IR.ModuleType{module: module, segments: alias_segs}
  end

  def transform({:{}, _, data}) do
    build_tuple_type_ir(data)
  end

  def transform({_, _} = data) do
    data
    |> Tuple.to_list()
    |> build_tuple_type_ir()
  end

  def transform({name, _, nil}) when is_atom(name) do
    %IR.Variable{name: name}
  end

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
