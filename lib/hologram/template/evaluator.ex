defmodule Hologram.Template.Evaluator do
  alias Hologram.Compiler.IR.ModuleAttributeOperator

  def evaluate(ir, state)

  def evaluate(%ModuleAttributeOperator{name: name}, state) do
    Map.get(state, name)
  end
end
