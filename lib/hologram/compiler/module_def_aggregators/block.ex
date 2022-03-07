alias Hologram.Compiler.IR.Block
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: Block do
  def aggregate(%{expressions: exprs}) do
    Enum.each(exprs, &ModuleDefAggregator.aggregate/1)
  end
end
