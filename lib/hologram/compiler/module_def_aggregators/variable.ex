# TODO: test

alias Hologram.Compiler.IR.Variable
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: Variable do
  def aggregate(_), do: nil
end
