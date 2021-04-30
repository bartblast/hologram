defmodule Hologram.Transpiler.MapKeyGenerator do
  alias Hologram.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}

  def generate(ast, context \\ [module_attributes: []])

  def generate(%AtomType{value: value}, _) do
    "~Hologram.Transpiler.AST.AtomType[#{value}]"
  end

  def generate(%BooleanType{value: value}, _) do
    "~Hologram.Transpiler.AST.BooleanType[#{value}]"
  end

  def generate(%IntegerType{value: value}, _) do
    "~Hologram.Transpiler.AST.IntegerType[#{value}]"
  end

  def generate(%StringType{value: value}, _) do
    "~Hologram.Transpiler.AST.StringType[#{value}]"
  end
end
