alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.StringType

defimpl Aggregator, for: StringType do
  def aggregate(_, module_defs), do: module_defs
end
