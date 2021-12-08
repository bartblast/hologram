# TODO: test

alias Hologram.Compiler.IR.NotSupportedExpression
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: NotSupportedExpression do
  require Logger

  def aggregate(ir) do
    logger_config = Application.fetch_env!(:logger, :console)
    Logger.configure_backend(:console, logger_config)

    """
    Not supported expression (compiler ignored it)
    #{inspect(ir)}
    """
    |> Logger.notice()
  end
end
