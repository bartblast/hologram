defmodule Hologram.Compiler.Builder do
  alias Hologram.Compiler.{Context, JSEncoder, Opts, Pruner}

  def build(module, module_defs, call_graph) do
    Pruner.prune(module, module_defs, call_graph)
    |> encode_module_defs()
  end

  defp encode_module_defs(module_defs) do
    Enum.reduce(module_defs, "", fn {_, module_def}, acc ->
      acc <> "\n" <> JSEncoder.encode(module_def, %Context{}, %Opts{})
    end)
  end
end
