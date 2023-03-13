# TODO: implement SourceFileStore and test

defmodule Hologram.Compiler.SourceFileAggregator do
  alias Hologram.Compiler.Reflection
  alias Hologram.Compiler.SourceFileStore

  def maybe_aggregate(module) do
    source_path = Reflection.source_path(module)

    unless SourceFileStore.has?(source_path) do
      Task.async(fn ->
        ir =
          source_path
          |> File.read!()
          |> Reflection.ir()

        SourceFileStore.put(source_path, ir)

        {ir, source_files} = Expander.expand(ir)
      end)
    end
  end
end
