defmodule Hologram.Transpiler.Generators.MapKeyGenerator do
  alias Hologram.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  
  def generate(%AtomType{value: value}) do
    "~Hologram.Transpiler.AST.AtomType[#{value}]"
  end

  def generate(%BooleanType{value: value}) do
    "~Hologram.Transpiler.AST.BooleanType[#{value}]"
  end

  def generate(%IntegerType{value: value}) do
    "~Hologram.Transpiler.AST.IntegerType[#{value}]"
  end

  def generate(%StringType{value: value}) do
    "~Hologram.Transpiler.AST.StringType[#{value}]"
  end
end
