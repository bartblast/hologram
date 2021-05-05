defmodule Hologram.Template.Evaluator do
  alias Hologram.Compiler.AST.ModuleAttributeOperator

  def evaluate(ast, state)

  def evaluate(%ModuleAttributeOperator{name: name}, state) do
    Map.get(state, name)
  end
end
