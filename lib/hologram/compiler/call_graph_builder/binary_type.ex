# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.BinaryType

defimpl CallGraphBuilder, for: BinaryType do
  def build(_, _, _, _), do: nil
end
