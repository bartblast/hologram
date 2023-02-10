defmodule Hologram.Compiler.Transformer do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR

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

  # TODO: implement anonymous functions with multiple clauses
  def transform({:fn, _, _} = ast) do
    %IR.NotSupportedExpression{
      type: :multi_clause_anonymous_function_type,
      ast: ast
    }
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

  def transform(nil) do
    %IR.NilType{}
  end

  def transform(ast) when is_binary(ast) do
    %IR.StringType{value: ast}
  end

  # --- OTHER IR ---

  def transform({:__block__, _, ast}) do
    ir = Enum.map(ast, &transform/1)
    %IR.Block{expressions: ir}
  end

  # --- HELPERS ---

  def transform_params(params) do
    params
    |> List.wrap()
    |> Enum.map(&transform/1)
  end
end
