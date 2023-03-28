defmodule Hologram.Compiler.Transformer do
  if Application.compile_env(:hologram, :debug_transformer) do
    use Interceptor.Annotated,
      config: %{
        {Hologram.Compiler.Transformer, :transform, 1} => [
          after: {Hologram.Compiler.Transformer, :debug, 2}
        ]
      }
  end

  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR

  def transform({{:., _, [{name, _, _}]}, _, args}) do
    %IR.AnonymousFunctionCall{
      name: name,
      args: transform_list(args)
    }
  end

  def transform(ast) when is_atom(ast) do
    %IR.AtomType{value: ast}
  end

  def transform({:__ENV__, _, _}) do
    %IR.EnvPseudoVariable{}
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

  def transform({:@, _, [{name, _, [ast]}]}) do
    %IR.ModuleAttributeDefinition{
      name: name,
      expression: transform(ast)
    }
  end

  def transform({:@, _, [{name, _, ast}]}) when not is_list(ast) do
    %IR.ModuleAttributeOperator{name: name}
  end

  def transform({:__MODULE__, _, _}) do
    %IR.ModulePseudoVariable{}
  end

  def transform({:__aliases__, [alias: module], _alias_segs}) when module != false do
    module_segs = Helpers.alias_segments(module)
    %IR.ModuleType{module: module, segments: module_segs}
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

  def transform({:__aliases__, _, segments}) do
    %IR.Alias{segments: segments}
  end

  def transform({{:., _, [module, function]}, _, args}) when not is_atom(module) do
    build_call_ir(module, function, args)
  end

  def transform({function, _, args}) when is_atom(function) and is_list(args) do
    build_call_ir(nil, function, args)
  end

  def transform({name, _, _}) when is_atom(name) do
    %IR.Symbol{name: name}
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

  defp build_call_ir(module, function, args) do
    new_module =
      case module do
        nil ->
          nil

        # TODO: uncomment after contextual call transformer is implemented
        # %IR.ModuleType{} ->
        #   module

        module ->
          transform(module)
      end

    %IR.Call{
      module: new_module,
      function: function,
      args: transform_list(args)
    }
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
