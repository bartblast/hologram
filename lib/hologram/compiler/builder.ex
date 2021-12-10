defmodule Hologram.Compiler.Builder do
  alias Hologram.Compiler.{Context, ModuleDefStore, JSEncoder, Opts, Pruner}
  require Logger

  def build(module, module_defs, call_graph) do
    Logger.debug("Started Pruner.prune/2 for #{module}")
    pruned_module_defs = Pruner.prune(module, module_defs, call_graph)
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
