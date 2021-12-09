# TODO: test

alias Hologram.Compiler.IR.NilType
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: NilType do
  def aggregate(_), do: nil
end
