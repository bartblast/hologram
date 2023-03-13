defmodule Hologram.Test.Fixtures.Commons.MemoryStore.Module1 do
  use Hologram.Commons.MemoryStore

  @dump_path "#{File.cwd!()}/tmp/test_fixture_memory_store_1.bin"

  @impl true
  def table_name, do: :test_fixture_memory_store_1

  @impl true
  def populate_table(_opts \\ []) do
    populate_table_from_file(@dump_path)
  end

  def dump_path, do: @dump_path
end
