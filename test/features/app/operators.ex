defmodule HologramFeatureTests.Operators do
  def a + b, do: a * b

  def a +++ b, do: a * b - a
end
