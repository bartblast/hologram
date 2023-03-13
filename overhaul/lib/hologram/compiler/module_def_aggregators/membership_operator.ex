# TODO: test

alias Hologram.Compiler.IR.MembershipOperator
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: MembershipOperator do
  def aggregate(%{left: left, right: right}) do
    ModuleDefAggregator.aggregate(left)
    ModuleDefAggregator.aggregate(right)
  end
end
