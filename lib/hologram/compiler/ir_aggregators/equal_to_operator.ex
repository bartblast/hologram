# TODO: test

alias Hologram.Compiler.IR.EqualToOperator
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: EqualToOperator do
  def aggregate(%{left: left, right: right}) do
    IRAggregator.aggregate(left)
    IRAggregator.aggregate(right)
  end
end
