# TODO: test

alias Hologram.Compiler.IR.BooleanAndOperator
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: BooleanAndOperator do
  def aggregate(%{left: left, right: right}) do
    IRAggregator.aggregate(left)
    IRAggregator.aggregate(right)
  end
end
