# TODO: test

alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.ListType

defimpl Aggregator, for: ListType do
  def aggregate(%{data: data}, module_defs) do
    Aggregator.aggregate(data, module_defs)
  end
end
