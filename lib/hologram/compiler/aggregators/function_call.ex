alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.{FunctionCall, ModuleType}

defimpl Aggregator, for: FunctionCall do
  def aggregate(%{module: module}, module_defs) do
    %ModuleType{module: module}
    |> Aggregator.aggregate(module_defs)
  end
end
