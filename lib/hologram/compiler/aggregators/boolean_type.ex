alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.BooleanType

defimpl Aggregator, for: BooleanType do
  def aggregate(_, module_defs), do: module_defs
end
