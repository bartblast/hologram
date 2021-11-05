alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.TupleType

defimpl Aggregator, for: TupleType do
  def aggregate(%{data: data}, module_defs) do
    Aggregator.aggregate(data, module_defs)
  end
end
