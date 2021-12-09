# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.NotSupportedExpression

defimpl CallGraphBuilder, for: NotSupportedExpression do
  def build(_, _, _), do: nil
end
