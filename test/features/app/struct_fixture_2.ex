defmodule HologramFeatureTests.StructFixture2 do
  defstruct items: []
end

defimpl Enumerable, for: HologramFeatureTests.StructFixture2 do
  def count(_enumerable) do
    {:error, __MODULE__}
  end

  def member?(_enumerable, _element) do
    {:error, __MODULE__}
  end

  def reduce(%{items: items}, acc, fun) do
    Enumerable.List.reduce(items, acc, fun)
  end

  def slice(_enumerable) do
    {:error, __MODULE__}
  end
end
