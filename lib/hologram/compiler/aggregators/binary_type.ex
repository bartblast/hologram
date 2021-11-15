alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.BinaryType

defimpl Aggregator, for: BinaryType do
  def aggregate(_, module_defs), do: module_defs
end
