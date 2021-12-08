# TODO: test

alias Hologram.Compiler.IR.BinaryType
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: BinaryType do
  def aggregate(_), do: nil
end
