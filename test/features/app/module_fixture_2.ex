defmodule HologramFeatureTests.ModuleFixture2 do
  def fun_1 do
    :a
  end

  defp fun_2 do
    :a
  end

  def fun_2_wrapper do
    fun_2()
  end

  def fun_3(x) do
    x
  end

  def fun_4(x, y) do
    {x, y}
  end

  def fun_5(1, x) do
    {1, x}
  end

  def fun_5(2, x) do
    {2, x}
  end

  def fun_5(3, x) do
    {3, x}
  end

  def fun_6 do
    :a
    :b
  end

  def fun_9(x = 3, y = 4) do
    {x, y}
  end

  def fun_9(x, y) do
    x = x + 10
    {x, y}
  end

  def fun_10 do
    raise RuntimeError, "my message"
  end
end
