alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.FunctionCall

defimpl Aggregator, for: FunctionCall do
  def aggregate(%{module: module, args: args}, module_defs) do
    module_defs = Aggregator.aggregate(module, module_defs)
    Aggregator.aggregate(args, module_defs)
  end
end
