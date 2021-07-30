defmodule Hologram.Template.Evaluator do
  alias Hologram.Compiler.IR.{IntegerType, ListType, ModuleAttributeOperator}

  def evaluate(ir, state)

  # TYPES

  def evaluate(%IntegerType{value: value}, _) do
    value
  end

  def evaluate(%ListType{data: data}, state) do
    Enum.map(data, &evaluate(&1, state))
  end

  # OPERATORS

  def evaluate(%ModuleAttributeOperator{name: name}, state) do
    Map.get(state, name)
  end
end
