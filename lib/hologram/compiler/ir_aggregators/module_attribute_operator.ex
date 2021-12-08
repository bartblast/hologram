# TODO: test

alias Hologram.Compiler.IR.ModuleAttributeOperator
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: ModuleAttributeOperator do
  def aggregate(_), do: nil
end
