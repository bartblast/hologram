# TODO: test

alias Hologram.Compiler.IR.DotOperator
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: DotOperator do
  def aggregate(%{left: left, right: right}) do
    IRAggregator.aggregate(left)
    IRAggregator.aggregate(right)
  end
end
