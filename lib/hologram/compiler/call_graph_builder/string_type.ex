# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.StringType

defimpl CallGraphBuilder, for: StringType do
  def build(_, _, _), do: nil
end
