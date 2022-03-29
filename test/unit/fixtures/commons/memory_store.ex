defmodule Hologram.Test.Fixtures.Commons.MemoryStore do
  use Hologram.Commons.MemoryStore

  @impl true
  def table_name, do: :test_fixture_memory_store

  @impl true
  def populate_table do
    %{key_1: :value_1, key_2: :value_2}
    |> Enum.each(fn {key, value} -> put(key, value) end)
  end
end
