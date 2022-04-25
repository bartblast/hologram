# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.FloatType

defimpl CallGraphBuilder, for: FloatType do
  def build(_, _, _, _), do: nil
end
