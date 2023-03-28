defmodule Hologram.Compiler.Transformer do
  if Application.compile_env(:hologram, :debug_transformer) do
    use Interceptor.Annotated,
      config: %{
        {Hologram.Compiler.Transformer, :transform, 1} => [
          after: {Hologram.Compiler.Transformer, :debug, 2}
        ]
      }
  end

  alias Hologram.Compiler.IR

  def transform({:__aliases__, _, segments}) do
    %IR.Alias{segments: segments}
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
    data = Enum.map(ast, &transform/1)
    %IR.ListType{data: data}
  end

  def transform({:@, _, [{name, _, [ast]}]}) do
    %IR.ModuleAttributeDefinition{
      name: name,
      expression: transform(ast)
    }
  end

  def transform({:@, _, [{name, _, ast}]}) when not is_list(ast) do
    %IR.ModuleAttributeOperator{name: name}
  end

  def transform({:{}, _, data}) do
    build_tuple_type_ir(data)
  end

  def transform({_, _} = data) do
    data
    |> Tuple.to_list()
    |> build_tuple_type_ir()
  end

  # preserve order:

  def transform({name, _, _}) when is_atom(name) do
    %IR.Symbol{name: name}
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
    data = Enum.map(data, &transform/1)
    %IR.TupleType{data: data}
  end
end
