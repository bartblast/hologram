defmodule Hologram.Compiler do
  alias Hologram.Compiler.Reflection
  alias Hologram.Compiler.SourceFileStore
  alias Hologram.Utils

  def compile(opts) do
    templatables = Reflection.list_templatables(opts)

    templatables =
      if opts[:templatables], do: templatables ++ opts[:templatables], else: templatables

    SourceFileStore.run()
    transform_source_files(templatables)
  end

  defp maybe_transform_source_file(module) do
    source_path = Reflection.source_path(module)

    unless SourceFileStore.has?(source_path) do
      SourceFileStore.lock(source_path)

      ir =
        source_path
        |> File.read!()
        |> Reflection.ir()
        |> Expander.expand()

      # {ir, source_files} = Expander.expand(ir)
      # TODO: transformer the new source files async

      SourceFileStore.put(source_path, ir)
    end
  end

  defp transform_source_files(modules) do
    modules
    |> Utils.map_async(&maybe_transform_source_file/1)
    |> Utils.await_tasks()
  end

  defp traverse(ir, _context \\ %{}) do
    ir
  end
end
