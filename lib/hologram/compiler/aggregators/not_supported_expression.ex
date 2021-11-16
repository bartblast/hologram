# TODO: test

alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.NotSupportedExpression

defimpl Aggregator, for: NotSupportedExpression do
  def aggregate(ir, module_defs) do
    "Not supported expression (compiler ignored it):\n-----\n#{inspect(ir)}\n-----"
    module_defs
  end
end
