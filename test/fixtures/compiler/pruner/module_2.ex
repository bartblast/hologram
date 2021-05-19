defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module2 do
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module3

  def action(:test_2, a, b) do
    Module3.test_3()
  end
end
