# TODO: test

alias Hologram.Compiler.IR.NilType
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: NilType do
  def aggregate(_), do: nil
end
