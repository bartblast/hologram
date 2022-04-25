# TODO: test

alias Hologram.Compiler.IR.FloatType
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: FloatType do
  def aggregate(_), do: nil
end
