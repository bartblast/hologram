alias Hologram.Compiler.IR.ModuleAttributeOperator
alias Hologram.Template.Evaluator

defimpl Evaluator, for: ModuleAttributeOperator  do
  def evaluate(%{name: name}, state) do
    Map.get(state, name)
  end
end
