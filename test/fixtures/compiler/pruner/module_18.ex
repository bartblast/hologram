defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module18 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module19

  def action(:test_1, _a, _b) do
    Module19.some_fun_1()
  end
end
