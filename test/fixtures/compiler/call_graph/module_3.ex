defmodule Hologram.Test.Fixtures.CallGraph.Module3 do
  def test_fun_1 do
    test_fun_2()
  end

  def test_fun_2, do: nil
end
