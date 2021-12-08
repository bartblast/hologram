alias Hologram.Compiler.IR.TupleType
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: TupleType do
  def aggregate(%{data: data}) do
    IRAggregator.aggregate(data)
  end
end
