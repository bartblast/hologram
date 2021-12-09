# TODO: test

alias Hologram.Compiler.IR.ModuleAttributeOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: ModuleAttributeOperator do
  def aggregate(_), do: nil
end
