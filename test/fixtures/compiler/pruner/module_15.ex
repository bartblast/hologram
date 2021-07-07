defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module15 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module16

  def action(:test_1, a, b) do
    Module16.some_fun()
  end
end
