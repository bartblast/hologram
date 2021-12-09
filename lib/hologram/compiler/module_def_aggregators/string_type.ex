# TODO: test

alias Hologram.Compiler.IR.StringType
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: StringType do
  def aggregate(_), do: nil
end
