# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.IntegerType

defimpl CallGraphBuilder, for: IntegerType do
  def build(_, _, _, _), do: nil
end
