defmodule Hologram.Transpiler.Builder.TestModule1 do
  alias Hologram.Transpiler.Builder.TestModule2
  alias Hologram.Transpiler.Builder.TestModule3

  def action(:test, a, b) do
    TestModule3.test_3()
  end
end
