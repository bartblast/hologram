# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.Variable

defimpl CallGraphBuilder, for: Variable do
  def build(_, _, _), do: nil
end
