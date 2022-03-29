defmodule Hologram.Test.Fixtures.Commons.MemoryStore do
  use Hologram.Commons.MemoryStore

  @impl true
  def dump_path, do: Path.dirname(__ENV__.file) <> "/memory_store.bin"

  @impl true
  def table_name, do: :test_fixture_memory_store
end
