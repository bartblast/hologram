# TODO: test

alias Hologram.Compiler.IR.BooleanType
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: BooleanType do
  def aggregate(_), do: nil
end
