# TODO: test

alias Hologram.Compiler.IR.BinaryType
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: BinaryType do
  def aggregate(_), do: nil
end
