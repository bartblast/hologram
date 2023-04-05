defmodule Hologram.Test.Fixtures.Commons.MemoryStore.Module2 do
  use Hologram.Commons.MemoryStore

  @impl MemoryStore
  def get(key) do
    if key do
      {:ok, "overriden_value_for_#{key}"}
    else
      :error
    end
  end
end
