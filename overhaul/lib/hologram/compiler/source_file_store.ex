defmodule Hologram.Compiler.SourceFileStore do
  use Hologram.Commons.MemoryStore

  @impl true
  def table_name, do: :hologram_source_file_store
end
