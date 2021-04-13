defmodule Hologram.TemplateEngine.Evaluator do
  alias Hologram.Transpiler.AST.ModuleAttribute

  def evaluate(ast, state)

  def evaluate(%ModuleAttribute{name: name}, state) do
    Map.get(state, name)
  end
end
