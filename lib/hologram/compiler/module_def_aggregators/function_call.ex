alias Hologram.Compiler.IR.FunctionCall
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: FunctionCall do
  def aggregate(%{module: module, args: args}) do
    ModuleDefAggregator.aggregate(module)
    ModuleDefAggregator.aggregate(args)
  end
end
