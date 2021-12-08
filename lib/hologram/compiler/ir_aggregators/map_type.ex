# TODO: test

alias Hologram.Compiler.IR.MapType
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: MapType do
  def aggregate(%{data: data}) do
    IRAggregator.aggregate(data)
  end
end
