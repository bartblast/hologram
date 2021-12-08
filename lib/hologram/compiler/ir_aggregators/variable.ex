# TODO: test

alias Hologram.Compiler.IR.Variable
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: Variable do
  def aggregate(_), do: nil
end
