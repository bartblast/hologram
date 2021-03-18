defmodule Holograf.Transpiler.Generator do
  alias Holograf.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Holograf.Transpiler.AST.MapType

  # PRIMITIVES

  def generate(%AtomType{value: value}) do
    "'#{value}'"
  end

  def generate(%BooleanType{value: value}) do
    "#{value}"
  end

  def generate(%IntegerType{value: value}) do
    "#{value}"
  end

  def generate(%StringType{value: value}) do
    "'#{value}'"
  end

  # DATA STRUCTURES

  def generate(%MapType{data: data}) do
    fields =
      Enum.map(data, fn {k, v} -> "#{generate(k)}: #{generate(v)}" end)
      |> Enum.join(", ")

    if fields != "" do
      "{ #{fields} }"
    else
      "{}"
    end
  end
end
