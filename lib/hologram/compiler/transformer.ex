defmodule Hologram.Compiler.Transformer do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.PatternDeconstructor

  @doc """
  Transforms Elixir AST to Hologram IR.

  ## Examples
      iex> ast = quote do 1 + 2 end
      {:+, [context: Elixir, imports: [{1, Kernel}, {2, Kernel}]], [1, 2]}
      iex> Transformer.transform(ast)
      %IR.AdditionOperator{left: %IR.IntegerType{value: 1}, right: %IR.IntegerType{value: 2}}
  """
  def transform(ast)

  # --- DATA TYPES ---

  def transform({:fn, _, [{:->, _, [params, body]}]}) do
    params = transform_params(params)
    arity = Enum.count(params)
    bindings = Helpers.aggregate_bindings_from_params(params)
    body = transform(body)

    %IR.AnonymousFunctionType{arity: arity, params: params, bindings: bindings, body: body}
  end

  def transform(ast) when is_atom(ast) and ast not in [nil, false, true] do
    %IR.AtomType{value: ast}
  end

  def transform(ast) when is_boolean(ast) do
    %IR.BooleanType{value: ast}
  end

  def transform(ast) when is_float(ast) do
    %IR.FloatType{value: ast}
  end

  def transform(ast) when is_integer(ast) do
    %IR.IntegerType{value: ast}
  end

  def transform({:%{}, _, data}) do
    {module, new_data} = Keyword.pop(data, :__struct__)

    data_ir =
      Enum.map(new_data, fn {key, value} ->
        {transform(key), transform(value)}
      end)

    if module do
      segments = Helpers.alias_segments(module)
      module_ir = %IR.ModuleType{module: module, segments: segments}
      %IR.StructType{module: module_ir, data: data_ir}
    else
      %IR.MapType{data: data_ir}
    end
  end

  def transform(nil) do
    %IR.NilType{}
  end

  def transform(ast) when is_binary(ast) do
    %IR.StringType{value: ast}
  end

  def transform({:%, _, [alias_ast, map_ast]}) do
    module = transform(alias_ast)
    data = transform(map_ast).data

    %IR.StructType{module: module, data: data}
  end

  # --- OPERATORS ---

  def transform({{:., _, [{:__aliases__, [alias: false], [:Access]}, :get]}, _, [data, key]}) do
    %IR.AccessOperator{
      data: transform(data),
      key: transform(key)
    }
  end

  def transform({:+, _, [left, right]}) do
    %IR.AdditionOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform([{:|, _, [head, tail]}]) do
    %IR.ConsOperator{
      head: transform(head),
      tail: transform(tail)
    }
  end

  def transform({:/, _, [left, right]}) do
    %IR.DivisionOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({{:., _, [left, right]}, [no_parens: true, line: _], []}) do
    %IR.DotOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({:==, _, [left, right]}) do
    %IR.EqualToOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({:<, _, [left, right]}) do
    %IR.LessThanOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({:=, _, [left, right]}) do
    left = transform(left)

    bindings =
      left
      |> PatternDeconstructor.deconstruct()
      |> Enum.map(fn path ->
        [head | tail] = Enum.reverse(path)
        access_path = [%IR.MatchAccess{} | Enum.reverse(tail)]
        %IR.Binding{name: head.name, access_path: access_path}
      end)

    %IR.MatchOperator{
      bindings: bindings,
      left: left,
      right: transform(right)
    }
  end

  def transform({:@, _, [{name, _, ast}]}) when not is_list(ast) and name != :spec do
    %IR.ModuleAttributeOperator{name: name}
  end

  def transform({:+, _, [value]}) do
    %IR.UnaryPositiveOperator{
      value: transform(value)
    }
  end

  # --- CONTROL FLOW ---

  def transform({{:., _, [{name, _, nil}]}, _, args}) do
    %IR.AnonymousFunctionCall{
      name: name,
      args: Enum.map(args, &transform/1)
    }
  end

  # --- PSEUDO-VARIABLES ---

  def transform({:__ENV__, _, _}) do
    %IR.EnvPseudoVariable{}
  end

  def transform({:__MODULE__, _, _}) do
    %IR.ModulePseudoVariable{}
  end

  # --- OTHER IR ---

  def transform({:__aliases__, _, segments}) do
    %IR.Alias{segments: segments}
  end

  def transform({:__block__, _, ast}) do
    ir = Enum.map(ast, &transform/1)
    %IR.Block{expressions: ir}
  end

  def transform({name, _, _}) when is_atom(name) do
    %IR.Symbol{name: name}
  end

  # --- TODO ---

  # TODO: implement anonymous functions with multiple clauses
  def transform({:fn, _, _} = ast) do
    %IR.NotSupportedExpression{
      type: :multi_clause_anonymous_function_type,
      ast: ast
    }
  end

  # --- HELPERS ---

  def transform_params(params) do
    params
    |> List.wrap()
    |> Enum.map(&transform/1)
  end
end
