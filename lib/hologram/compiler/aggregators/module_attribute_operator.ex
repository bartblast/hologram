# TODO: test

alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.ModuleAttributeOperator

defimpl Aggregator, for: ModuleAttributeOperator do
  def aggregate(_, module_defs), do: module_defs
end
