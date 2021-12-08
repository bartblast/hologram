# TODO: test

alias Hologram.Compiler.IR.IntegerType
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: IntegerType do
  def aggregate(_), do: nil
end
