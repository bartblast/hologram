# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.AtomType

defimpl CallGraphBuilder, for: AtomType do
  def build(_, _, _), do: nil
end
