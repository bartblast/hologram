# TODO: test

alias Hologram.Compiler.IR.BooleanType
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: BooleanType do
  def aggregate(_), do: nil
end
