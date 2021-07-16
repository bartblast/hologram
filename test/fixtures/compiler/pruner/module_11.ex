defmodule Hologram.Test.Fixtures.Compiler.Pruner.Module11 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Pruner.Module12

  def action(:test_1, _a, _b) do
    Module12.some_fun_1()
  end
end
