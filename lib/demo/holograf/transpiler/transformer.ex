defmodule Holograf.Transpiler.Transformer do
  alias Holograf.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Holograf.Transpiler.AST.MapType
  alias Holograf.Transpiler.AST.Variable

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

  # DATA STRUCTURES

  def transform({:%{}, _, map}) do
    data = Enum.map(map, fn {k, v} -> {transform(k), transform(v)} end)
    %MapType{data: data}
  end

  # OTHER

  def transform({name, _, nil}) when is_atom(name) do
    %Variable{name: name}
  end
end
