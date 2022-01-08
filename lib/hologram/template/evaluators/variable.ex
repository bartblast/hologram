alias Hologram.Compiler.IR.Variable
alias Hologram.Template.Evaluator

defimpl Evaluator, for: Variable do
  def evaluate(%{name: name}, bindings) do
    # DEFER: raise custom Hologram error here, see: https://github.com/segmetric/hologram/issues/27
    Map.fetch!(bindings, name)
  end
end
