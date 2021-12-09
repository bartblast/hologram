# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.NilType

defimpl CallGraphBuilder, for: NilType do
  def build(_, _, _), do: nil
end
