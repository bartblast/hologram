# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.ModuleAttributeOperator

defimpl CallGraphBuilder, for: ModuleAttributeOperator do
  def build(_, _, _), do: nil
end
