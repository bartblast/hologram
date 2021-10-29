alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.FunctionDefinition

defimpl Aggregator, for: FunctionDefinition do
  def aggregate(%{body: body}, module_defs) do
    Aggregator.aggregate(body, module_defs)
  end
end
