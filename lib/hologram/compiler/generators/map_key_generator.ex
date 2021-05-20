defmodule Hologram.Compiler.MapKeyGenerator do
  alias Hologram.Compiler.IR.{AtomType, BooleanType, IntegerType, StringType}

  def generate(ir, context \\ [])

  def generate(%AtomType{value: value}, _) do
    "~atom[#{value}]"
  end

  def generate(%BooleanType{value: value}, _) do
    "~boolean[#{value}]"
  end

  def generate(%IntegerType{value: value}, _) do
    "~integer[#{value}]"
  end

  def generate(%StringType{value: value}, _) do
    "~string[#{value}]"
  end
end
