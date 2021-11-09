alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.FunctionCall

defimpl Aggregator, for: FunctionCall do
  def aggregate(%{module: module}, module_defs) do
    Aggregator.aggregate(module, module_defs)
  end
end
