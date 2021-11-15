# TODO: test

alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.Variable

defimpl Aggregator, for: Variable do
  def aggregate(_, module_defs), do: module_defs
end
