alias Hologram.Compiler.IR.ModuleType
alias Hologram.Template.Evaluator

defimpl Evaluator, for: ModuleType do
  def evaluate(%{module: module}, _) do
    module
  end
end
