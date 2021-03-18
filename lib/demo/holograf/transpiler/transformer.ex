defmodule Holograf.Transpiler.Transformer do
  alias Holograf.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}

  def transform(ast)

  # PRIMITIVES

  # boolean must be before atom
  def transform(ast) when is_boolean(ast) do
    %BooleanType{value: ast}
  end

  def transform(ast) when is_atom(ast) do
    %AtomType{value: ast}
  end

  def transform(ast) when is_integer(ast) do
    %IntegerType{value: ast}
  end

  def transform(ast) when is_binary(ast) do
    %StringType{value: ast}
  end
end
