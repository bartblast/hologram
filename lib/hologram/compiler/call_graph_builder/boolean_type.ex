# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.BooleanType

defimpl CallGraphBuilder, for: BooleanType do
  def build(_, _, _), do: nil
end
