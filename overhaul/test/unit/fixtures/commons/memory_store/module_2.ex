defmodule Hologram.Test.Fixtures.Commons.MemoryStore.Module2 do
  use Hologram.Commons.MemoryStore

  @impl true
  def get(key) do
    if key do
      {:ok, "result_for_#{key}"}
    else
      :error
    end
  end

  @impl true
  def table_name, do: :test_fixture_memory_store_2
end
