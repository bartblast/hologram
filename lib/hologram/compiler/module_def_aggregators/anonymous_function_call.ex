alias Hologram.Compiler.IR.AnonymousFunctionCall
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: AnonymousFunctionCall do
  def aggregate(%{args: args}) do
    ModuleDefAggregator.aggregate(args)
  end
end
