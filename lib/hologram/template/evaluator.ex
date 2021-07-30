defmodule Hologram.Template.Evaluator do
  alias Hologram.Compiler.IR.{IntegerType, ModuleAttributeOperator}

  def evaluate(ir, state)

  # TYPES

  def evaluate(%IntegerType{value: value}, _) do
    value
  end

  # OPERATORS

  def evaluate(%ModuleAttributeOperator{name: name}, state) do
    Map.get(state, name)
  end
end
