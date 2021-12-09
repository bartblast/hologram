# TODO: test

alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.NotSupportedExpression

defimpl Aggregator, for: NotSupportedExpression do
  require Logger

  def aggregate(ir, module_defs) do
    """
    Not supported expression (compiler ignored it)
    #{inspect(ir)}
    """
    |> Logger.notice()

    module_defs
  end
end
