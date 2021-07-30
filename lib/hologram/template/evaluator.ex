defmodule Hologram.Template.Evaluator do
  alias Hologram.Compiler.IR.{FunctionCall, IntegerType, ListType, ModuleAttributeOperator}

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

  # OTHER

  def evaluate(%FunctionCall{module: module, function: function, params: params}, state) do
    params = Enum.map(params, &evaluate(&1, state))
    apply(module, function, params)
  end
end
