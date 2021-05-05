defmodule Hologram.Compiler.MapKeyGenerator do
  alias Hologram.Compiler.AST.{AtomType, BooleanType, IntegerType, StringType}

  def generate(ast, context \\ [])

  def generate(%AtomType{value: value}, _) do
    "~Hologram.Compiler.AST.AtomType[#{value}]"
  end

  def generate(%BooleanType{value: value}, _) do
    "~Hologram.Compiler.AST.BooleanType[#{value}]"
  end

  def generate(%IntegerType{value: value}, _) do
    "~Hologram.Compiler.AST.IntegerType[#{value}]"
  end

  def generate(%StringType{value: value}, _) do
    "~Hologram.Compiler.AST.StringType[#{value}]"
  end
end
