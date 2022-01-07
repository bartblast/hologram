alias Hologram.Compiler.IR.Variable
alias Hologram.Template.Evaluator

defimpl Evaluator, for: Variable do
  def evaluate(%{name: name}, bindings) do
    bindings[name]
  end
end
