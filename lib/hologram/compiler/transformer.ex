defmodule Hologram.Compiler.Transformer do
  @doc """
  Transforms Elixir AST to Hologram IR.

  ## Examples
      iex> ast = quote do 1 + 2 end
      {:+, [context: Elixir, imports: [{1, Kernel}, {2, Kernel}]], [1, 2]}
      iex> Transformer.transform(ast)
      %IR.AdditionOperator{left: %IR.IntegerType{value: 1}, right: %IR.IntegerType{value: 2}}
  """
  def transform(ast)
end
