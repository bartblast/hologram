defmodule Hologram.TemplateEngine.Evaluator do
  alias Hologram.Transpiler.AST.ModuleAttributeOperator

  def evaluate(ast, state)

  def evaluate(%ModuleAttributeOperator{name: name}, state) do
    Map.get(state, name)
  end
end
