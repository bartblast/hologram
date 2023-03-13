# TODO: test

alias Hologram.Compiler.IR.AtomType
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: AtomType do
  def aggregate(_), do: nil
end
