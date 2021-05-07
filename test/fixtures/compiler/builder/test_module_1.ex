defmodule Hologram.Compiler.Builder.TestModule1 do
  alias Hologram.Compiler.Builder.TestModule2
  alias Hologram.Compiler.Builder.TestModule3

  def action(:test, a, b) do
    TestModule3.test_3()
  end
end
