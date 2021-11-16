# TODO: test

alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.StructType

defimpl Aggregator, for: StructType do
  def aggregate(%{data: data}, module_defs) do
    Aggregator.aggregate(data, module_defs)
  end
end
