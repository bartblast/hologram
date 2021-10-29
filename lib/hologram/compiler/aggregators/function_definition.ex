alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.FunctionDefinition

defimpl Aggregator, for: FunctionDefinition do
  def aggregate(%{body: body}, module_defs) do
    Enum.reduce(body, module_defs, &Aggregator.aggregate/2)
  end
end
