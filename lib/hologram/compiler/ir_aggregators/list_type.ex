# TODO: test

alias Hologram.Compiler.IR.ListType
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: ListType do
  def aggregate(%{data: data}) do
    IRAggregator.aggregate(data)
  end
end
