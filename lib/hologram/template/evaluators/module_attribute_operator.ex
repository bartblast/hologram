alias Hologram.Compiler.IR.ModuleAttributeOperator
alias Hologram.Template.Evaluator

defimpl Evaluator, for: ModuleAttributeOperator do
  def evaluate(%{name: name}, bindings) do
    Map.get(bindings, name)
  end
end
