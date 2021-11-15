# TODO: test

alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.NilType

defimpl Aggregator, for: NilType do
  def aggregate(_, module_defs), do: module_defs
end
