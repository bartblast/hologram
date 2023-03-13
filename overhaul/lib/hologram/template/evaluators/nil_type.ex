alias Hologram.Compiler.IR.NilType
alias Hologram.Template.Evaluator

defimpl Evaluator, for: NilType do
  def evaluate(_, _) do
    nil
  end
end
