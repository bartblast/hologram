# TODO: test

alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.IntegerType

defimpl Aggregator, for: IntegerType do
  def aggregate(_, module_defs), do: module_defs
end
