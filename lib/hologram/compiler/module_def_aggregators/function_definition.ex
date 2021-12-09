alias Hologram.Compiler.IR.FunctionDefinition
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: FunctionDefinition do
  def aggregate(%{body: body}) do
    ModuleDefAggregator.aggregate(body)
  end
end
