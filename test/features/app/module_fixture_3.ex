defmodule HologramFeatureTests.ModuleFixture3 do
  def is_integer(term), do: Kernel.is_integer(term)

  def reverse(list), do: Enum.reverse(list)
end
