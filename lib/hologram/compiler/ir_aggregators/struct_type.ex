# TODO: test

alias Hologram.Compiler.IR.StructType
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: StructType do
  def aggregate(%{data: data}) do
    IRAggregator.aggregate(data)
  end
end
