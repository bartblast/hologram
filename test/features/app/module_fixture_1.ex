defmodule HologramFeatureTests.ModuleFixture1 do
  defp private_fun(x, y) do
    {x, y}
  end

  def public_fun(x, y) do
    private_fun(x, y)
  end
end
