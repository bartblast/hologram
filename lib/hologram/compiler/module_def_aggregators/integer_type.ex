# TODO: test

alias Hologram.Compiler.IR.IntegerType
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: IntegerType do
  def aggregate(_), do: nil
end
