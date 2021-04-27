defmodule Hologram.Transpiler.Eliminator.TestModule2 do
  alias Hologram.Transpiler.Eliminator.TestModule3

  def action(:test_2, a, b) do
    TestModule3.test_3()
  end
end
