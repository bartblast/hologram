defmodule Hologram.Compiler.Builder do
  alias Hologram.Compiler.{Context, IRAggregator, IRStore, JSEncoder, Opts, Pruner}
  require Logger

  def build(module) do
    Logger.debug("Started IRAggregator.aggregate/1 for #{module}")
    IRAggregator.aggregate(module)
    Logger.debug("Finished IRAggregator.aggregate/1 for #{module}")

    module_defs = IRStore.get_all()

    Logger.debug("Started Pruner.prune/2 for #{module}")
    pruned_module_defs = Pruner.prune(module_defs, module)
    Logger.debug("Finished Pruner.prune/2 for #{module}")

    Logger.debug("Started encode_module_defs/1 for #{module}")
    result = encode_module_defs(pruned_module_defs)
    Logger.debug("Finished encode_module_defs/1 for #{module}")

    result
  end

  defp encode_module_defs(module_defs) do
    Enum.reduce(module_defs, "", fn {_, module_def}, acc ->
      acc <> "\n" <> JSEncoder.encode(module_def, %Context{}, %Opts{})
    end)
  end
end
