alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.AtomType

defimpl Aggregator, for: AtomType do
  def aggregate(_, module_defs), do: module_defs
  end
end
