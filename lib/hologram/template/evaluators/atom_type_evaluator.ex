alias Hologram.Compiler.IR.AtomType
alias Hologram.Template.Evaluator

defimpl Evaluator, for: AtomType do
  def evaluate(%{value: value}, _) do
    value
  end
end
