# TODO: test

alias Hologram.Compiler.IR.MatchOperator
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: MatchOperator do
  def aggregate(%{right: right}) do
    IRAggregator.aggregate(right)
  end
end
