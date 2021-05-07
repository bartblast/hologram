defmodule Hologram.Compiler.Eliminator.TestModule2 do
  alias Hologram.Compiler.Eliminator.TestModule3

  def action(:test_2, a, b) do
    TestModule3.test_3()
  end
end
