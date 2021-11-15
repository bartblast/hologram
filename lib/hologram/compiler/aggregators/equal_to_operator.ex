# TODO: test

alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.EqualToOperator

defimpl Aggregator, for: EqualToOperator do
  def aggregate(%{left: left, right: right}, module_defs) do
    module_defs = Aggregator.aggregate(left, module_defs)
    Aggregator.aggregate(right, module_defs)
  end
end
